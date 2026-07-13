import Foundation
import Libbox
import Network
import NetworkExtension
// sing-box 1.13's libbox references UIKit (UIApplication background-task APIs)
// that 1.12 did not. The extension's own Swift never touches UIKit, but importing
// it here auto-links UIKit.framework so the libbox symbols resolve at link time.
import UIKit

/// The sing-box Network Extension for iOS. Reads the config the app wrote to the
/// shared App Group, sets up the TUN from sing-box's requested options, and runs
/// the core. The provider is the libbox PlatformInterface (TUN + interface
/// monitor), mirroring the Android VpnService host.
///
/// openTun and the interface monitor are adapted from sing-box-for-apple's
/// ExtensionPlatformInterface; if you hit routing edge cases, cross-check against
/// that reference (it is built against this same Libbox.xcframework).
class PacketTunnelProvider: NEPacketTunnelProvider {
  static let appGroup = "group.online.novaproxy.novaClient"

  private var commandServer: LibboxCommandServer?
  private var pathMonitor: NWPathMonitor?

  override func startTunnel(options _: [String: NSObject]?) async throws {
    guard let container = FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup) else {
      throw NSError(domain: "Nova", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group missing"])
    }
    let base = container.path
    let setup = LibboxSetupOptions()
    setup.basePath = base
    setup.workingPath = container.appendingPathComponent("work").path
    setup.tempPath = container.appendingPathComponent("tmp").path
    try? FileManager.default.createDirectory(atPath: setup.workingPath, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(atPath: setup.tempPath, withIntermediateDirectories: true)
    var setupErr: NSError?
    LibboxSetup(setup, &setupErr)

    let config = try String(contentsOf: container.appendingPathComponent("config.json"), encoding: .utf8)

    // sing-box 1.13 folded the box service into the command server: instead of
    // LibboxNewService(config, platform) + a separate command server, the command
    // server now takes the PlatformInterface (self) and owns the service. We
    // create it, start its App Group control socket (so the main app can attach a
    // status client for live traffic), then start the service from the config,
    // which is what dials the TUN via openTun below.
    var err: NSError?
    guard let server = LibboxNewCommandServer(commandServerHandler, self, &err), err == nil else {
      throw err ?? NSError(domain: "Nova", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create command server"])
    }
    try server.start()
    // Pass a real (empty) options object, NOT nil: despite the ObjC param being
    // marked nullable, libbox 1.13's StartOrReloadService dereferences it
    // (options.AutoRedirect) with no nil check, so nil panics the extension and
    // the tunnel never comes up.
    try server.startOrReloadService(config, options: LibboxOverrideOptions())
    commandServer = server
  }

  override func stopTunnel(with _: NEProviderStopReason) async {
    pathMonitor?.cancel()
    pathMonitor = nil
    try? commandServer?.closeService()
    try? commandServer?.close()
    commandServer = nil
  }

  private lazy var commandServerHandler = CommandServerHandler(provider: self)
}

/// Minimal command-server handler. The traffic/status stream the app consumes
/// needs a running server; the system-proxy and reload hooks are not used on
/// the iOS packet-tunnel path, so they answer with safe defaults.
private final class CommandServerHandler: NSObject, LibboxCommandServerHandlerProtocol {
  private weak var provider: PacketTunnelProvider?
  init(provider: PacketTunnelProvider) { self.provider = provider }

  func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
    let status = LibboxSystemProxyStatus()
    status.available = false
    status.enabled = false
    return status
  }

  // 1.13 replaced postServiceClose with serviceStop; both are unused on the
  // packet-tunnel path (the extension owns its own lifecycle).
  func serviceStop() throws {}

  func serviceReload() throws {}

  func setSystemProxyEnabled(_ enabled: Bool) throws {}

  // Added in sing-box 1.13's command-server handler.
  func writeDebugMessage(_ message: String?) {}
}

// MARK: - LibboxPlatformInterface

extension PacketTunnelProvider: LibboxPlatformInterfaceProtocol {
  func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
    guard let options, let ret0_ else {
      throw NSError(domain: "Nova", code: 3, userInfo: [NSLocalizedDescriptionKey: "Nil tun options"])
    }
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    settings.mtu = NSNumber(value: options.getMTU())

    // DNS (a single boxed server address)
    if let dnsBox = try? options.getDNSServerAddress(), !dnsBox.value.isEmpty {
      settings.dnsSettings = NEDNSSettings(servers: [dnsBox.value])
    }

    // IPv4 addresses + default route.
    var v4addr: [String] = [], v4mask: [String] = []
    if let it = options.getInet4Address() {
      while it.hasNext() { let p = it.next()!; v4addr.append(p.address()); v4mask.append(p.mask()) }
    }
    if !v4addr.isEmpty {
      let v4 = NEIPv4Settings(addresses: v4addr, subnetMasks: v4mask)
      // Included routes: what sing-box wants tunneled (default route if none).
      var inc: [NEIPv4Route] = []
      if let it = options.getInet4RouteAddress() {
        while it.hasNext() { let p = it.next()!; inc.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask())) }
      }
      v4.includedRoutes = inc.isEmpty ? [NEIPv4Route.default()] : inc
      // Excluded routes: sing-box lists the proxy server IPs (and LAN) here so
      // the core's own outbound connection to them goes out the real interface
      // instead of looping back through the tunnel. Without this the upload
      // SYN escapes but the return path loops — connected, upload, zero download.
      var exc: [NEIPv4Route] = []
      if let it = options.getInet4RouteExcludeAddress() {
        while it.hasNext() { let p = it.next()!; exc.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask())) }
      }
      if !exc.isEmpty { v4.excludedRoutes = exc }
      settings.ipv4Settings = v4
    }

    // IPv6 addresses + routes.
    var v6addr: [String] = []; var v6prefix: [NSNumber] = []
    if let it = options.getInet6Address() {
      while it.hasNext() { let p = it.next()!; v6addr.append(p.address()); v6prefix.append(NSNumber(value: p.prefix())) }
    }
    if !v6addr.isEmpty {
      let v6 = NEIPv6Settings(addresses: v6addr, networkPrefixLengths: v6prefix)
      var inc6: [NEIPv6Route] = []
      if let it = options.getInet6RouteAddress() {
        while it.hasNext() { let p = it.next()!; inc6.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix()))) }
      }
      v6.includedRoutes = inc6.isEmpty ? [NEIPv6Route.default()] : inc6
      var exc6: [NEIPv6Route] = []
      if let it = options.getInet6RouteExcludeAddress() {
        while it.hasNext() { let p = it.next()!; exc6.append(NEIPv6Route(destinationAddress: p.address(), networkPrefixLength: NSNumber(value: p.prefix()))) }
      }
      if !exc6.isEmpty { v6.excludedRoutes = exc6 }
      settings.ipv6Settings = v6
    }

    // System HTTP/HTTPS proxy. When the config's tun `platform.http_proxy` is
    // enabled, sing-box runs the proxy listener and hands us its address here;
    // we register it via NEProxySettings so apps that honour the system proxy
    // (and skip the packet route) still get tunneled. Without this some apps get
    // no proxy at all.
    if options.isHTTPProxyEnabled() {
      let proxySettings = NEProxySettings()
      let server = NEProxyServer(
        address: options.getHTTPProxyServer(),
        port: Int(options.getHTTPProxyServerPort()))
      proxySettings.httpServer = server
      proxySettings.httpsServer = server
      proxySettings.httpEnabled = true
      proxySettings.httpsEnabled = true
      // Only constrain the match list if sing-box actually names domains;
      // leaving it nil (the default) makes the proxy apply to ALL connections,
      // which is what we want to catch route-skipping apps.
      var matchDomains: [String] = []
      if let it = options.getHTTPProxyMatchDomain() {
        while it.hasNext() { matchDomains.append(it.next()) }
      }
      if !matchDomains.isEmpty { proxySettings.matchDomains = matchDomains }
      var bypassDomains: [String] = []
      if let it = options.getHTTPProxyBypassDomain() {
        while it.hasNext() { bypassDomains.append(it.next()) }
      }
      if !bypassDomains.isEmpty { proxySettings.exceptionList = bypassDomains }
      settings.proxySettings = proxySettings
    }

    // setTunnelNetworkSettings is async; bridge to sync for libbox.
    let sem = DispatchSemaphore(value: 0)
    var applyError: Error?
    setTunnelNetworkSettings(settings) { error in applyError = error; sem.signal() }
    sem.wait()
    if let applyError { throw applyError }

    // The TUN file descriptor for libbox. The private `socket.fileDescriptor`
    // KVC path works on older iOS but returns nil on newer releases (e.g.
    // iOS 18+/26), so fall back to libbox's own tunnel-fd lookup — without this
    // the tunnel fails to come up a few seconds in ("No tun fd").
    if let fd = packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32, fd != -1 {
      ret0_.pointee = fd
      return
    }
    let loopFd = LibboxGetTunnelFileDescriptor()
    if loopFd != -1 {
      ret0_.pointee = loopFd
    } else {
      throw NSError(domain: "Nova", code: 4, userInfo: [NSLocalizedDescriptionKey: "No tun fd"])
    }
  }

  // Added in sing-box 1.12's LibboxPlatformInterface. We provide neither a
  // custom local DNS transport nor a platform certificate list, so sing-box uses
  // its own DNS handling (our config's remote/local servers) and the bundled
  // system trust store. Returning nil is the "use defaults" contract.
  func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }
  func systemCertificates() -> LibboxStringIteratorProtocol? { nil }
  func useProcFS() -> Bool { false }
  func underNetworkExtension() -> Bool { true }
  func includeAllNetworks() -> Bool { false }
  // Let sing-box bind outbound sockets to the real default interface itself
  // (via startDefaultInterfaceMonitor below). Returning true here with an empty
  // autoDetectControl left the proxy's sockets unbound, so requests went out
  // but nothing came back ("connected, upload only, no download").
  func usePlatformAutoDetectControl() -> Bool { false }
  func autoDetectControl(_: Int32) throws {}
  func clearDNSCache() {}

  func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
    guard let listener else { return }
    let monitor = NWPathMonitor()
    pathMonitor = monitor
    // Block until the first path update is delivered, so sing-box knows the real
    // default interface BEFORE it dials any outbound. Returning early let it bind
    // outbounds to the tunnel itself -> loop -> connected but zero download.
    let semaphore = DispatchSemaphore(value: 0)
    monitor.pathUpdateHandler = { path in
      self.report(listener, path)
      semaphore.signal()
      monitor.pathUpdateHandler = { path in self.report(listener, path) }
    }
    monitor.start(queue: DispatchQueue.global())
    semaphore.wait()
  }

  private func report(_ listener: LibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath) {
    guard path.status != .unsatisfied, let iface = path.availableInterfaces.first else {
      listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
      return
    }
    listener.updateDefaultInterface(iface.name, interfaceIndex: Int32(iface.index),
                                    isExpensive: path.isExpensive, isConstrained: path.isConstrained)
  }

  func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
    pathMonitor?.cancel()
    pathMonitor = nil
  }

  // sing-box enumerates interfaces here to bind outbound sockets to the physical
  // one. Throwing (as before) left it unable to bind -> traffic looped -> zero
  // download. Return the live interfaces from the path monitor.
  func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
    guard let path = pathMonitor?.currentPath, path.status != .unsatisfied else {
      return InterfaceArray([])
    }
    var out: [LibboxNetworkInterface] = []
    for it in path.availableInterfaces {
      let n = LibboxNetworkInterface()
      n.name = it.name
      n.index = Int32(it.index)
      switch it.type {
      case .wifi: n.type = LibboxInterfaceTypeWIFI
      case .cellular: n.type = LibboxInterfaceTypeCellular
      case .wiredEthernet: n.type = LibboxInterfaceTypeEthernet
      default: n.type = LibboxInterfaceTypeOther
      }
      out.append(n)
    }
    return InterfaceArray(out)
  }

  // 1.13 changed this to return a LibboxConnectionOwner instead of an out-param;
  // process/owner lookup is unsupported in the iOS extension, so return nil.
  func findConnectionOwner(_: Int32, sourceAddress _: String?, sourcePort _: Int32,
                           destinationAddress _: String?, destinationPort _: Int32) throws -> LibboxConnectionOwner {
    throw NSError(domain: "Nova", code: 6, userInfo: [NSLocalizedDescriptionKey: "unsupported"])
  }

  func readWIFIState() -> LibboxWIFIState? { nil }
  func send(_: LibboxNotification?) throws {}
}

/// Bridges a Swift array of interfaces to libbox's iterator protocol so the core
/// can enumerate the device's network interfaces.
private final class InterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
  private var iterator: IndexingIterator<[LibboxNetworkInterface]>
  private var current: LibboxNetworkInterface?
  init(_ array: [LibboxNetworkInterface]) { iterator = array.makeIterator() }
  func hasNext() -> Bool {
    current = iterator.next()
    return current != nil
  }
  func next() -> LibboxNetworkInterface? { current }
}
