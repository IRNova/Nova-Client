# Changelog

## v1.2.0-beta (2026-07-21)

A big anti-censorship update, by Vahid Hashemi.

- More protocols: SOCKS, HTTP, and plain WireGuard join VLESS, VMess, Trojan, Shadowsocks (including 2022), Hysteria2, and AmneziaWG import.
- Google relay upgrades: import your whole relay setup from one link or QR, a domain-fronting mode that reaches Google's edge even when the relay's own address is blocked, and a full-tunnel option that carries real traffic through Google to your own VPS when everything else is down.
- Find a working setup: when the block stops your usual setup, Nova tests each TLS fingerprint on your real network, measures which get through, and keeps the fastest.
- Anti-censorship tuning you can see: the Routing screen shows which TLS fingerprint is protecting you and lets you override it (Chrome, Firefox, Safari, iOS, Edge, Randomized) or leave it on Auto.
- Speed test: measure your real download and upload speed in the Stats tab.
- Hysteria2 speed boost (Brutal) for better throughput on throttled networks; set your line speed in Routing.
- Now targets Android 15.
- Builds: Android in this release. macOS and Windows to follow.

## v1.1.1-beta (2026-07-16)

Connectivity and panel fixes, by Vahid Hashemi.

- Cloudflare connect fixed: the in-app Cloudflare sign-in and API calls could fail with a TLS handshake error. Requests now run real TLS with the correct hostname, so connecting and deploying a panel work reliably.
- Panel password now saves in the app: right after deploying a new panel, setting the admin password could fail because the fresh worker was not serving its certificate yet. Nova now waits out that warm-up and retries, and if it still cannot reach the panel it tells you to finish setup in a browser.
- Android VPN routing fixed: outbound sockets were binding to the tunnel interface on Android 9 and newer, which broke Cloudflare-direct calls and slowed browsing. Traffic now uses the real Wi-Fi or cellular link.
- Android live speed meter: the dashboard now shows real upload and download speeds instead of staying at 0.
- Builds: Android and macOS (Apple Silicon) refreshed for this release. The Windows build carries over from v1.1.0-beta pending a fresh Windows build.

## v1.1.0-beta (2026-07-13)

- Redesigned node list with per-node location, SNI, and TLS fingerprint
- Search your nodes by name, country, protocol, address, or SNI
- Free-service header and community links
- Route every .ir domain direct so Iranian sites always load
- Farsi localization for the Routing and Servers screens

## v1.0.0-beta (2026-07-10)

First public beta of Nova Client.

- Proxy client with profiles, subscriptions, and routing controls, powered by a sing-box core
- Nova Radar: built-in Cloudflare clean-IP scanner (fetch, scan, TCP + TLS verify, latency sort, one-tap apply)
- Bilingual UI: English and Farsi (RTL)
- Dark-first Nova design language
- Builds: Android APK, macOS (Apple Silicon) DMG and zip, Windows zip
