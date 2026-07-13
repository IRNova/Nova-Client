# sing-box core integration

Nova Client's data path is a modified **sing-box** core. This document tracks
how the Dart UI, the config layer, and the native hosts fit together, and what
remains to make Connect actually proxy traffic.

## Layers

```
 UI (screens)
   │  ProxyController (abstract: state + traffic)
   ├── MockProxyController        ← active today: simulated connect/traffic
   └── SingboxProxyController     ← real path
         │  builds config in Dart …
         │     parseShareLink(uri) → ProxyNode
         │     SingboxConfig.build(node, options) → sing-box JSON
         │  … then drives the native core over platform channels
         ▼
   Native host (per platform)
         Android  : VpnService + libbox      ← TODO
         iOS/macOS: NEPacketTunnelProvider   ← TODO
         Desktop  : TUN helper               ← TODO
```

## Done (this milestone)

- **Share-link parser** (`lib/src/core/proxy/singbox/share_link.dart`) —
  VLESS, Trojan, Shadowsocks (SIP002 + legacy), unit-tested.
- **Config builder** (`singbox_config.dart`) — TUN inbound, DNS (proxy/local
  split), per-protocol outbound (TLS + WS/gRPC transport), rule-based routing
  with optional ad-block + Iran-bypass rule-sets. Unit-tested.
- **`SingboxProxyController`** now builds a real config and sends it over the
  `start` method channel. It is **not yet the app's active controller**
  (`main.dart` still uses `MockProxyController`) — swap it once the native host
  below exists.

## Channel contract

MethodChannel `nova.proxy/control`:

- `start(configJson: String)` — start the tunnel with the given sing-box config.
- `stop()` — stop the tunnel.
- `status()` — return the current state name.

EventChannel `nova.proxy/events` emits maps:

- `{ "type": "state", "value": "connected" }`
- `{ "type": "traffic", "up": bps, "down": bps, "upTotal": bytes, "downTotal": bytes }`
- `{ "type": "error", "message": "text" }`

## TODO — Android (first target)

1. **Commit an Android project** (`flutter create --platforms=android .`) so
   native sources can live in-repo (today the APK workflow generates it in CI).
2. **Bundle the core**: build sing-box's `libbox` to an AAR via gomobile
   (`gomobile bind -target=android ./experimental/libbox`) — needs Go + the
   Android NDK — and drop it in `android/app/libs/`. (Or reuse the AAR from the
   official sing-box-for-android releases.)
3. **`NovaVpnService`** (`VpnService`): build the TUN, hand its fd + the config
   JSON to `libbox`, run the box, and post a foreground notification.
4. **Channel bridge** in `MainActivity`/a plugin: implement `start/stop/status`
   and stream `state`/`traffic` on the EventChannel from libbox's status hooks.
5. **Manifest**: `BIND_VPN_SERVICE`, `FOREGROUND_SERVICE`, the `<service>` entry,
   and the VPN-consent flow (`VpnService.prepare`).
6. Flip `main.dart` to `SingboxProxyController()` and test on a device.

> Steps 2 and 6 need a native toolchain (NDK/gomobile) and a physical device,
> which aren't available in the cloud build environment — they're the hand-off
> points for local/device work.
