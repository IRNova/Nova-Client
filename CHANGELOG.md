# Changelog

## v1.6.0-beta (2026-08-15)

Exact-match the anti-censorship fragmentation, by the Nova team.

- The SNI-block bypass now splits the connection handshake into the exact same
  packet sizes as the PattNG method, byte for byte, instead of an approximation.
  On the strictest networks the approximation was not enough; this build should
  behave the same as PattNG there. It stays off by default, applies only to the
  clean-IP servers, and turns itself on when nothing else connects.

## v1.5.1-beta (2026-08-15)

SNI-block bypass fixes from tester feedback, by the Nova team.

- The server list no longer says "blocked" for every server when the SNI-block
  bypass is on. The test it runs cannot reproduce the bypass, so it now says
  those servers are tested when you connect, instead of a false blocked.
- SNI-block bypass on Windows. The handshake fragmentation it used has a step
  that a normal Windows install cannot perform, so it never connected. Windows
  now uses the part that works, which is also the part that matters for hiding
  the server name.

## v1.5.0-beta (2026-08-15)

For the networks that block the worker domain itself, by the Nova team.

- SNI-block bypass, for networks that have started blocking the workers.dev
  and pages.dev domains themselves. Nova can now run the profile that testers
  found gets through in PattNG: plain TLS with a fixed cipher list instead of a
  browser fingerprint, and a fragmented handshake, on the clean-IP servers only.
  It stays off by default. If every server in a subscription fails to carry
  traffic, Nova turns it on for that subscription by itself, reconnects, and
  tells you; there is also a switch at the top of the server list. Links from
  cf-optimizor (fp=unsafe, cs, fm) import as-is, and a hardened Nova server
  re-shares in that same format so it pastes into PattNG.

## v1.4.0-beta (2026-08-15)

Every platform on the same code, and a cleaner app, by the Nova team.

- A modernized interface. The dashboard, server list, node list, settings and
  first-run screens were reworked around one clear focus per screen, with
  colour reserved for state and the measured verdict the most legible thing on
  a server row. Nothing animates while the app is idle any more, which is a
  real battery win: the connect orb used to repaint sixty times a second all
  day.
- Windows and macOS get the same VPN core as the phone. The desktop core had
  been an older stock build with no WireGuard, no NaiveProxy and no AmneziaWG in
  it, so those servers failed on desktop while working on Android. Both desktop
  cores are now built from the same source and patch as the Android one.
- iOS now requires iOS 15 or later, ahead of Apple's 2027 requirement.
- NaiveProxy servers work now. Nova Server has always been able to create one,
  and the phone app's VPN core could always run it, but the app could not read
  the link, so a NaiveProxy server appeared in no client at all. On desktop it
  says plainly that this build's core cannot run it, instead of the core dying
  at startup.
- A subscription no longer loses servers in silence. If it contains something
  Nova cannot run, the server list says how many and what kind, so a short list
  is explained instead of looking like configs went missing.

## v1.3.0-beta (2026-08-14)

An honesty update, by the Nova team. Nova now tells you what it actually knows
about your servers instead of guessing, and shows you what it and the VPN core
are doing.

- The server you pick is the server you get. If the one you chose connects but
  carries no traffic, Nova now tells you and stays on your choice instead of
  quietly connecting through a different one while the list still showed yours
  as selected. If your server has disappeared from the subscription, it says
  that too, rather than switching in silence.
- Ping numbers are real now. Nova used to show the time it took to open a
  connection, which succeeds against Cloudflare's network for any address at
  all, so every config looked healthy even on a network where none of them
  worked. Each server is now tested by actually talking to it, and where
  possible by sending a real request through it and waiting for the answer. A
  server that cannot be tested from outside says so instead of borrowing a
  number it did not earn.
- Server locations are honest. A config sent with a clean Cloudflare address
  used to be labelled with wherever that address happened to resolve, which is
  not where your traffic comes out. Those now show the name the panel gave them
  and say they are fronted, and configs that use a domain get a real flag,
  which they never used to.
- New Logs screen in Settings, with Nova's own log and the VPN core's log kept
  separate. Copying strips passwords, UUIDs and subscription tokens first, so a
  log is safe to send to support. Detailed core logging is a switch on that
  screen, off by default.
- AmneziaWG now actually works in Nova. The app has been building correct
  AmneziaWG configurations all along and handing them to a core that did not
  have the protocol in it, so a server's AmneziaWG worked in the official
  Amnezia apps and not here. Nova's core is now built with AmneziaWG.
- Nova also checks its own core before it tries. If a build ever ships without
  AmneziaWG again, it says so instead of connecting to nothing.
- The VPN core is now included for every processor type the app runs on. Older
  32-bit phones and x86 devices were installing an app that had no core for
  them, so they could open Nova and never connect. The download is larger
  because of it.

## v1.2.0-beta (2026-07-21)

A big anti-censorship update, by the Nova team.

- More protocols: SOCKS, HTTP, and plain WireGuard join VLESS, VMess, Trojan, Shadowsocks (including 2022), Hysteria2, and AmneziaWG import.
- Google relay upgrades: import your whole relay setup from one link or QR, a domain-fronting mode that reaches Google's edge even when the relay's own address is blocked, and a full-tunnel option that carries real traffic through Google to your own VPS when everything else is down.
- Find a working setup: when the block stops your usual setup, Nova tests each TLS fingerprint on your real network, measures which get through, and keeps the fastest.
- Anti-censorship tuning you can see: the Routing screen shows which TLS fingerprint is protecting you and lets you override it (Chrome, Firefox, Safari, iOS, Edge, Randomized) or leave it on Auto.
- Speed test: measure your real download and upload speed in the Stats tab.
- Hysteria2 speed boost (Brutal) for better throughput on throttled networks; set your line speed in Routing.
- Now targets Android 15.
- Builds: Android APK, macOS (Apple Silicon) DMG and zip, and Windows portable ZIP.

## v1.1.1-beta (2026-07-16)

Connectivity and panel fixes, by the Nova team.

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
