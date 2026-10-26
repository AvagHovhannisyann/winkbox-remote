# WinkBox Remote

An iPhone remote for the Rostelecom WinkBox 2 (Android TV box): an Apple-TV-style touch pad or arrows, the Siri
Remote's buttons, a screen of big app tiles that open apps on the TV, and typing into the TV's search boxes.

It talks to the box directly over the home Wi-Fi through the box's network debugging (ADB, port 5555). Button presses
are written straight into the box's own remote-control input (`/dev/input/event0`, the `aml_keypad` device), so they
arrive instantly and behave exactly like the box's remote: holding an arrow repeats, holding OK long-presses.
Typing and opening apps go through a shell on the box (`input text`, `am start`).

## Building

The app is built without Xcode on the user's Mac: every push to `main` builds it on GitHub's Macs
(`.github/workflows/build.yml` runs `build.sh`) and publishes `WinkRemote.ipa` as the
[latest release](../../releases/tag/latest). `build.sh` can also build locally, either with Xcode or with the Mac's
Command Line Tools plus the iPhone SDK pulled out of an Xcode .xip by `Tools/extract-sdk.py`.

There are no image files: the app tiles are drawn in SwiftUI (`BrandArt` in `App/UI/AppsView.swift`) and the app
icon is drawn by `Tools/icon/main.swift` during the build.

## Installing

With [xtool](https://github.com/xtool-org/xtool) logged in to an Apple ID (`xtool setup`) and the iPhone plugged in:

```bash
curl -fLO https://github.com/AvagHovhannisyann/winkbox-remote/releases/download/latest/WinkRemote.ipa
xtool install WinkRemote.ipa
```

An app signed with a free Apple ID stops opening after 7 days; installing it again renews it. The first time it
connects, the TV asks "Allow USB debugging?": tick "Always allow from this computer" and choose OK.

## Layout

| | |
|---|---|
| `App/Core/ADB.swift` | The ADB wire protocol over Network.framework: handshake, RSA auth, streams with flow control |
| `App/Core/ADBKey.swift` | The app's RSA key and adb's public-key format (mincrypt `RSAPublicKey`) |
| `App/Core/TV.swift` | The box: connection lifecycle, raw key events into the keypad, shell commands, the app list |
| `App/UI/` | SwiftUI screens: remote (touch pad / arrows / buttons), apps, typing, settings |
| `Tools/icon` | Draws the app icon |
