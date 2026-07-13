import Flutter
import Foundation
import Libbox
import NetworkExtension

/// iOS implementation of the `nova.proxy/control` MethodChannel + `nova.proxy/events`
/// EventChannel that the Flutter `SingboxProxyController` drives. It manages the
/// Packet Tunnel (the sing-box Network Extension) via NETunnelProviderManager:
/// the config is handed to the extension through the shared App Group, and the
/// connection state is streamed back from NEVPNStatus.
final class NovaProxyHost: NSObject, FlutterStreamHandler {
  static let appGroup = "group.online.novaproxy.novaClient"
  static let tunnelBundleId = "online.novaproxy.novaClient.NovaTunnel"

  private var eventSink: FlutterEventSink?
  private var manager: NETunnelProviderManager?
  private var statusClient: LibboxCommandClient?
  private var libboxReady = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let host = NovaProxyHost()
    let control = FlutterMethodChannel(name: "nova.proxy/control", binaryMessenger: registrar.messenger())
    control.setMethodCallHandler(host.handle)
    let events = FlutterEventChannel(name: "nova.proxy/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(host)

    NotificationCenter.default.addObserver(
      host, selector: #selector(host.statusChanged),
      name: .NEVPNStatusDidChange, object: nil)
  }

  // MARK: - MethodChannel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      guard let args = call.arguments as? [String: Any],
            let config = args["configJson"] as? String else {
        result(FlutterError(code: "args", message: "configJson required", details: nil))
        return
      }
      // Optional bundled rule-set files (name -> bytes), written next to the
      // config so the lean iOS config can reference them as local rule-sets.
      let ruleSets = (args["ruleSets"] as? [String: FlutterStandardTypedData]) ?? [:]
      start(config: config, ruleSets: ruleSets, result: result)
    case "stop":
      stopTunnel(result: result)
    case "status":
      // Load the existing tunnel manager if we don't have it yet (e.g. the app
      // was relaunched while the VPN kept running), so we report the REAL status
      // instead of "disconnected".
      loadManagerIfNeeded { [weak self] in
        guard let self else { result("disconnected"); return }
        let status = self.manager?.connection.status ?? .invalid
        if status == .connected { self.startStatusClient() }
        result(self.stateName(status))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The token the Dart config uses in local rule-set paths; replaced with the
  /// real App Group container path here (the app and extension share it, so an
  /// absolute path written by the app is valid inside the extension too).
  private static let ruleSetBaseToken = "__NOVA_BASE__"

  private func start(config: String, ruleSets: [String: FlutterStandardTypedData],
                     result: @escaping FlutterResult) {
    // Write the config where the extension can read it (shared App Group).
    guard let container = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else {
      result(FlutterError(code: "appgroup", message: "App Group not configured", details: nil))
      return
    }
    do {
      // Write any bundled rule-set files (e.g. geosite-ir.srs) into the shared
      // container, then point the config's placeholder paths at them.
      for (name, data) in ruleSets {
        try data.data.write(to: container.appendingPathComponent(name), options: .atomic)
      }
      let resolved = config.replacingOccurrences(
        of: Self.ruleSetBaseToken, with: container.path)
      try resolved.write(to: container.appendingPathComponent("config.json"),
                         atomically: true, encoding: .utf8)
    } catch {
      result(FlutterError(code: "write", message: error.localizedDescription, details: nil))
      return
    }

    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
      guard let self else { return }
      if let error { result(FlutterError(code: "load", message: error.localizedDescription, details: nil)); return }
      let mgr = managers?.first ?? NETunnelProviderManager()
      let proto = (mgr.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
      proto.providerBundleIdentifier = Self.tunnelBundleId
      proto.serverAddress = "Nova"
      mgr.protocolConfiguration = proto
      mgr.localizedDescription = "Nova"
      mgr.isEnabled = true
      // Auto-reconnect. If iOS terminates the extension under memory pressure
      // (e.g. a speed test's throughput burst pushes the ~50MB Network
      // Extension over its limit), an on-demand "connect" rule brings the tunnel
      // straight back instead of leaving the user stranded offline. This is only
      // enabled while a session is active; `stopTunnel` disables it so a
      // user-initiated Disconnect genuinely stays off and does not auto-reconnect.
      let onDemand = NEOnDemandRuleConnect()
      onDemand.interfaceTypeMatch = .any
      mgr.onDemandRules = [onDemand]
      mgr.isOnDemandEnabled = true
      mgr.saveToPreferences { error in
        if let error { result(FlutterError(code: "save", message: error.localizedDescription, details: nil)); return }
        // Reload so the saved configuration is applied before starting.
        mgr.loadFromPreferences { _ in
          self.manager = mgr
          do {
            try mgr.connection.startVPNTunnel()
            result(nil)
          } catch {
            result(FlutterError(code: "start", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  /// User-initiated Disconnect. On-demand is turned off (and saved) *before*
  /// stopping the tunnel so iOS won't immediately auto-reconnect the way it's
  /// designed to after an unexpected extension kill. Loads the manager first in
  /// case the app was relaunched while the tunnel kept running.
  private func stopTunnel(result: @escaping FlutterResult) {
    loadManagerIfNeeded { [weak self] in
      guard let self, let mgr = self.manager else { result(nil); return }
      mgr.isOnDemandEnabled = false
      mgr.onDemandRules = []
      mgr.saveToPreferences { _ in
        mgr.connection.stopVPNTunnel()
        result(nil)
      }
    }
  }

  /// Loads the already-configured tunnel manager into `self.manager` if we don't
  /// have a reference yet, so status queries after an app relaunch see the live
  /// connection instead of nil.
  private func loadManagerIfNeeded(_ completion: @escaping () -> Void) {
    if manager != nil { completion(); return }
    NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
      self?.manager = managers?.first
      completion()
    }
  }

  // MARK: - State stream

  @objc private func statusChanged() {
    let status = manager?.connection.status ?? .invalid
    emit(["type": "state", "value": stateName(status)])
    // Attach/detach the libbox status client so the dashboard gets live
    // download/upload throughput, not a frozen zero.
    switch status {
    case .connected:
      startStatusClient()
    default:
      stopStatusClient()
    }
  }

  // MARK: - Live traffic stats

  /// libbox's setup must run once in this process before a command client can
  /// find the extension's command socket. It points at the same shared App
  /// Group paths the extension uses.
  private func ensureLibboxSetup() {
    if libboxReady { return }
    guard let container = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else { return }
    let setup = LibboxSetupOptions()
    setup.basePath = container.path
    setup.workingPath = container.appendingPathComponent("work").path
    setup.tempPath = container.appendingPathComponent("tmp").path
    var err: NSError?
    LibboxSetup(setup, &err)
    libboxReady = (err == nil)
  }

  /// Serializes the status-client lifecycle off the main thread. `LibboxSetup`
  /// (in `ensureLibboxSetup`) and the client connect are the heavy calls; running
  /// them here instead of on the platform/main thread is what stops the app from
  /// freezing for a beat when it's cold-launched (returned to) while the tunnel
  /// is already up. A serial queue also makes every `statusClient` mutation
  /// thread-safe.
  private let statusQueue = DispatchQueue(label: "online.novaproxy.novaClient.status")

  private func startStatusClient() {
    statusQueue.async { [weak self] in
      guard let self, self.statusClient == nil else { return }
      self.ensureLibboxSetup()
      let options = LibboxCommandClientOptions()
      // 1.13 replaced the single `command` field with a command list.
      options.addCommand(LibboxCommandStatus)
      options.statusInterval = Int64(NSEC_PER_SEC) // one status push per second
      guard let client = LibboxNewCommandClient(StatusHandler(host: self), options)
      else { return }
      self.statusClient = client
      // The extension's server may take a beat to bind after the tunnel reports
      // connected; retry a few times before giving up.
      self.connectStatusClientLocked(client, attempt: 0)
    }
  }

  /// Runs on `statusQueue`.
  private func connectStatusClientLocked(_ client: LibboxCommandClient, attempt: Int) {
    do {
      try client.connect()
    } catch {
      guard statusClient === client, attempt < 5 else { return }
      statusQueue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        guard let self, self.statusClient === client else { return }
        self.connectStatusClientLocked(client, attempt: attempt + 1)
      }
    }
  }

  private func stopStatusClient() {
    statusQueue.async { [weak self] in
      guard let self, let client = self.statusClient else { return }
      self.statusClient = nil
      try? client.disconnect()
      self.emit(["type": "traffic", "up": 0, "down": 0, "upTotal": 0, "downTotal": 0])
    }
  }

  fileprivate func onStatus(_ message: LibboxStatusMessage) {
    emit([
      "type": "traffic",
      "up": message.uplink,
      "down": message.downlink,
      "upTotal": message.uplinkTotal,
      "downTotal": message.downlinkTotal,
    ])
  }

  private func stateName(_ s: NEVPNStatus) -> String {
    switch s {
    case .connected: return "connected"
    case .connecting, .reasserting: return "connecting"
    case .disconnecting: return "disconnecting"
    default: return "disconnected"
    }
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { self.eventSink?(event) }
  }

  // FlutterStreamHandler
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

/// Receives the libbox status stream and forwards only the traffic numbers to
/// the host. Every other callback is a required-but-unused protocol stub.
private final class StatusHandler: NSObject, LibboxCommandClientHandlerProtocol {
  private weak var host: NovaProxyHost?
  init(host: NovaProxyHost) { self.host = host }

  func writeStatus(_ message: LibboxStatusMessage?) {
    guard let message else { return }
    host?.onStatus(message)
  }

  func connected() {}
  func disconnected(_ message: String?) {}
  func clearLogs() {}
  func initializeClashMode(_ modeList: LibboxStringIteratorProtocol?, currentMode: String?) {}
  func updateClashMode(_ newMode: String?) {}
  func write(_ events: LibboxConnectionEvents?) {}
  func writeGroups(_ message: LibboxOutboundGroupIteratorProtocol?) {}
  func writeLogs(_ messageList: LibboxLogIteratorProtocol?) {}
  // Added in sing-box 1.13's command-client handler; we drive log level from the
  // config, so this is a no-op.
  func setDefaultLogLevel(_ level: Int32) {}
}
