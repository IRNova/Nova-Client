# Nova Client on iOS

iOS runs the sing-box core in a **Network Extension** (Packet Tunnel Provider),
driven by the same `nova.proxy/control` MethodChannel the Android host uses, so
the whole Flutter UI and Dart logic work unchanged.

## What's already in the repo
- **Core**: `Libbox.xcframework` in `ios/Frameworks/` (device + simulator;
  gitignored, rebuildable, see below).
- **App-side host**: `ios/Runner/NovaProxyHost.swift` (the MethodChannel /
  EventChannel via `NETunnelProviderManager`), registered in `AppDelegate.swift`.
- **Extension**: `ios/NovaTunnel/PacketTunnelProvider.swift` (the libbox
  PlatformInterface: openTun + interface monitor + service lifecycle), plus
  `Info.plist` and `NovaTunnel.entitlements`.
- **Entitlements**: `ios/Runner/Runner.entitlements` (NetworkExtension + App
  Group `group.online.novaproxy.novaClient`).
- **Dart**: `main.dart` already routes iOS to `SingboxProxyController`.

## Remaining (Xcode, with the Apple Developer account @irnova_proxy)
These steps create the extension target and wire the provided files into it.

1. **Add the target**: File > New > Target > **Network Extension** (Packet Tunnel
   Provider). Name it **NovaTunnel**, bundle id
   `online.novaproxy.novaClient.NovaTunnel`. Delete the auto-generated
   `PacketTunnelProvider.swift`/`Info.plist` and instead **add the existing files**
   from `ios/NovaTunnel/` to this target.
2. **Add `NovaProxyHost.swift`** to the Runner target (if not auto-added).
3. **Frameworks**: add `ios/Frameworks/Libbox.xcframework` to the **NovaTunnel**
   target ("Do Not Embed").
4. **Signing & Capabilities** on **both** Runner and NovaTunnel:
   - Network Extensions (Packet Tunnel)
   - App Groups -> `group.online.novaproxy.novaClient`
   - Point each target at its `.entitlements` file (already provided).
   - Select your team; let Xcode create the provisioning profiles.
5. **Run on a real device** (the simulator's NE support is limited).

## Rebuild the core
Current core: **sing-box v1.12.25** (upgraded from v1.11.15 on 2026-07-04 to get
TLS fragmentation, added upstream in 1.12.0).
```sh
git clone --depth 1 -b v1.12.25 https://github.com/sagernet/sing-box.git
cd sing-box
go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.8   # 1.12.x wants 0.1.8
go install github.com/sagernet/gomobile/cmd/gobind@v0.1.8
PATH="$PATH:$(go env GOPATH)/bin" go run ./cmd/internal/build_libbox -target apple -platform ios
cp -R Libbox.xcframework /path/to/nova-app/ios/Frameworks/
```

### Post-upgrade wiring the 1.12 core requires (already applied)
- **Link `libresolv`**: the 1.12 core calls the system resolver (`res_9_ninit`
  etc.). Both the Runner and NovaTunnel targets link Libbox, so BOTH need
  `OTHER_LDFLAGS = -lresolv` (set in `project.pbxproj`), else the app fails to
  link with `Undefined symbol: _res_9_ninit/_nsearch/_nclose`.
- **Two new `LibboxPlatformInterface` methods** in `PacketTunnelProvider.swift`:
  `localDNSTransport() -> LibboxLocalDNSTransportProtocol?` and
  `systemCertificates() -> LibboxStringIteratorProtocol?`, both return `nil`
  (use defaults). Note the `...Protocol` suffix on gomobile `id<...>` types.
- **TLS fragmentation** is emitted in `singbox_config.dart _tls()` as the outbound
  TLS keys `fragment` / `fragment_fallback_delay` (NOT `tls_fragment`, which is
  the route-rule spelling). Skipped for Reality nodes.

## Honest status
- The Swift was written against this exact `Libbox.xcframework` API but **not yet
  compiled** (the target doesn't exist until step 1). Expect to fix small
  signature/protocol-name details on the first Xcode build (the generated header
  uses names like `LibboxPlatformInterfaceProtocol`, `LibboxTunOptionsProtocol`).
- `openTun` and the interface monitor are adapted from the canonical
  **sing-box-for-apple** `ExtensionPlatformInterface`; if routing misbehaves,
  diff against that project (it targets the same framework).
- Live traffic stats from the extension are a TODO (state is wired via
  `NEVPNStatus`); the dashboard shows connected/disconnected today.
