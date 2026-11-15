# Fixtures

Text the Android tools print, kept so parsers can be tested without an SDK.

Captured from real tools (SDK Manager 22.0, Android CLI 23, `avdmanager`), user name replaced by `test`:

- `sdkmanager-list-22.txt` — `sdkmanager --list`, Available Packages cut down to the rows DroidDesk reads
- `avdmanager-list-device.txt` — `avdmanager list device`
- `avdmanager-list-avd.txt` — `avdmanager list avd`
- `sdkmanager-list-23.txt` — `android sdk list --all`, the two-space column layout of Android CLI 23, cut down like the one above

Written by hand from the documented layout, because the real output needs another SDK state:

- `sdkmanager-list-newer-22.txt` — `sdkmanager --list --newer` with an Available Updates table
- `avdmanager-list-avd-missing-image.txt` — a device whose system image was removed
- `adb-devices.txt` — `adb devices` with several states
- `adb-emu-avd-name.txt` — `adb emu avd name`
- `sdkmanager-license-prompt.txt` — what `sdkmanager --install` prints before it waits for an answer
- `sdkmanager-install-failure.txt` — a failed install

Replace a hand-written file with a real capture when one is at hand.
