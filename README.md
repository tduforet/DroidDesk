# DroidDesk

A small, native Mac app that sets up the official Android SDK and runs Android emulators, without installing Android Studio.

DroidDesk is a graphical layer over Google's own command-line tools (`sdkmanager`, `avdmanager`, `emulator`, `adb`). It installs them, downloads a system image, creates a virtual device, and starts it. The SDK it leaves behind is a standard one, so Expo, React Native, Flutter, Gradle, and `adb` work with it as usual.

> DroidDesk is an independent project. It is not affiliated with or endorsed by Google. Android is a trademark of Google LLC.

## Who it is for

- Developers building with Expo, React Native, Flutter, or native Android who want an emulator but not a full IDE.
- Front-end developers who need an Android device to test on.
- Anyone who prefers a lightweight editor but still wants a supported SDK.

## What it does

**Guided setup.** On a Mac with no SDK, DroidDesk opens a setup screen that:

1. lets you keep the default SDK folder (`~/Library/Android/sdk`) or choose another one,
2. downloads the official command-line tools, checks their SHA-256, and installs them,
3. installs platform-tools, the emulator, the newest stable Android platform and build-tools, and a matching Google Play `arm64-v8a` system image,
4. shows each SDK license and waits for you to accept it,
5. creates a Pixel virtual device,
6. starts it and tells you when it has finished booting.

Each step is read back from disk, so an interrupted setup picks up where it stopped. You can skip it, and run it again from Settings.

**Dashboard.** Shows whether `sdkmanager`, `avdmanager`, `adb`, and `emulator` are installed and working, with their versions, and installs or updates them.

**SDK Packages.** Install and uninstall Android platforms and build-tools (API 36 and newer).

**Virtual Devices.**
- Create a device from a Pixel profile and an installed system image.
- Start and stop devices. A device is marked *Ready* only once `adb` sees it and Android reports that it has booted.
- Cold boot (start without the saved snapshot) and wipe data (factory reset, with a confirmation).
- Delete a device after confirming.
- Download system images for API 36 and newer.

**Activity.** Every install, removal, and emulator command, with its exact command line, exit status, and output. *Copy Report* puts a diagnostic report on your clipboard.

**Settings.** Choose where the SDK and the virtual devices live. Nothing is moved or deleted when you change a folder. You can also remove the SDK and run the guided setup again.

## Requirements

- macOS 26 or later.
- An Apple Silicon Mac is the supported target. The recommended system images are `arm64-v8a`.
- Disk space for the SDK and a system image (several GB).
- An internet connection for the first setup.

## Install

There is no signed release yet, so for now DroidDesk is built from source:

```sh
git clone https://github.com/tduforet/DroidDesk.git
cd DroidDesk
xcodebuild -project DroidDesk.xcodeproj -scheme DroidDesk -configuration Release \
  -derivedDataPath .derivedData build
open .derivedData/Build/Products/Release/DroidDesk.app
```

You need Xcode with the macOS 26 SDK. The app is built on your own Mac, so macOS does not quarantine it.

## Where things live

| What | Where |
| --- | --- |
| Android SDK | `~/Library/Android/sdk` by default, or the folder you pick |
| Virtual devices | `~/.android/avd` by default, or the folder you pick |
| DroidDesk's own settings | The standard macOS preferences for `app.droiddesk.macos` |

DroidDesk looks for an SDK in this order: the folder chosen in the app, `ANDROID_SDK_ROOT`, `ANDROID_HOME`, then the default folder. For virtual devices it uses the folder chosen in the app, then `ANDROID_AVD_HOME`, then `~/.android/avd`. Apps opened from the Finder do not see variables set in your shell profile, so use Settings if you rely on them.

## Privacy

DroidDesk has no accounts and no analytics, and it sends no logs or system information anywhere. It talks to Google to download the command-line tools, and the Android tools it runs talk to Google's SDK repository to list and download packages. Everything else stays on your Mac.

DroidDesk never uses `sudo`. All locations are writable by your user.

## Limitations

- Platforms, build-tools, and system images start at API 36. Google Play phone images for `arm64-v8a` are the only ones offered for new devices.
- It is not a replacement for Android Studio. It does not build, sign, or profile apps, and it has no logcat viewer or APK installer.
- Other tools' output formats change over time. DroidDesk reads `sdkmanager` 22 and Android CLI 23 output and keeps the raw output in Activity when something does not parse.
- Starting a real emulator is not covered by the automated tests, since it needs real hardware.

## Development

```sh
# Build and open the app
xcodebuild -project DroidDesk.xcodeproj -scheme DroidDesk -configuration Debug \
  -derivedDataPath .derivedData build
open .derivedData/Build/Products/Debug/DroidDesk.app

# Run the tests
xcodebuild test -project DroidDesk.xcodeproj -scheme DroidDesk -destination 'platform=macOS'
```

The code is SwiftUI with Swift Concurrency, and all subprocesses run through one command runner without a shell. The tests use stored output from the real Android tools (`DroidDeskTests/Fixtures`) and a scratch folder in place of your home, so they never touch your SDK or your devices.

`Scripts/make-dmg.sh` builds a Release app and packs it into `dist/DroidDesk-<version>.dmg`, with a SHA-256 file next to it. The app is ad-hoc signed and not notarized, so on the first launch macOS asks you to confirm it in *System Settings → Privacy & Security → Open Anyway*.

`Scripts/make-icon.swift` redraws the app icon.

## License

DroidDesk is free software, released under the [GNU General Public License, version 3](LICENSE). You can use, study, change, and share it. If you distribute a modified version, you must do so under the same license and make its source available.

Copyright © 2026 Thomas Duforet.

DroidDesk does not include the Android SDK. It downloads Google's tools, which come with their own license that you accept during setup.
