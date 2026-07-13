# Nova Client, desktop and cross-platform notes

One Flutter codebase targets Android, macOS, Windows, iOS, and Linux. The proxy
data path is sing-box. On Android it's the VpnService + libbox host; on desktop
it's the bundled sing-box binary driven from pure Dart
(`lib/src/core/proxy/desktop_proxy_controller.dart`); iOS will use a Network
Extension.

## The bundled core binaries

The desktop binaries live in `assets/bin/` and are **not** committed (build
artifacts). Rebuild them with Go (>= 1.21):

```sh
# macOS (Apple Silicon)
GOOS=darwin GOARCH=arm64 go install -tags "with_gvisor,with_quic,with_utls,with_clash_api" \
  github.com/sagernet/sing-box/cmd/sing-box@v1.11.15
cp "$(go env GOPATH)/bin/sing-box" assets/bin/sing-box-macos-arm64

# Windows (x64)
GOOS=windows GOARCH=amd64 go install -tags "with_gvisor,with_quic,with_utls,with_clash_api" \
  github.com/sagernet/sing-box/cmd/sing-box@v1.11.15
cp "$(go env GOPATH)/bin/windows_amd64/sing-box.exe" assets/bin/sing-box-windows-amd64.exe
```

The controller picks the binary by platform + arch (`_assetName`), extracts it
to the app support dir, runs it with a local mixed inbound, points the OS proxy
at it, and reads the Clash API for traffic.

## Building per platform

```sh
flutter build macos     # this machine
flutter build windows   # on a Windows machine with Visual Studio (Desktop C++)
flutter build apk        # Android
flutter build ios        # on a Mac with Xcode + an Apple Developer account
```

### System proxy behaviour
- **macOS**: `networksetup` needs admin, so the app authorizes once via an
  `osascript` prompt. `manageSystemProxy: false` skips it (the local SOCKS proxy
  on `127.0.0.1:2080` is still usable manually).
- **Windows**: sets the WinINET proxy under HKCU (no admin needed). Changes
  apply to new connections; a session refresh can be added later for instant
  effect.

A privileged helper + full TUN (a seamless, no-prompt full VPN) is a planned
upgrade over the system-proxy approach.
