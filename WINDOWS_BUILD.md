# Building Nova Client on Windows

Everything needed is in this repo (including the bundled sing-box core), so it's
three steps.

## 1. Install the tools (once)
- **Flutter** (stable): https://docs.flutter.dev/get-started/install/windows
- **Visual Studio 2022** with the **"Desktop development with C++"** workload
  (Flutter needs this to build Windows apps). The free Community edition is fine.
- Run `flutter doctor` and make sure "Windows" shows a check.

## 2. Get the code
```powershell
git clone https://github.com/iiviirv/nova-app.git
cd nova-app
flutter pub get
```

## 3. Build and run
```powershell
flutter run -d windows         # run it directly, or:
flutter build windows          # produces a release build
```
The built app is at `build\windows\x64\runner\Release\nova_client.exe`.

## Notes
- The bundled core is `assets\bin\sing-box-windows-amd64.exe` (already in the repo).
- On Windows the app sets the system proxy under HKCU, so it does **not** need
  administrator rights.
- First launch shows onboarding (language, then how to start). Connect from the
  home screen; deploy or import a panel from the Configs screen.
