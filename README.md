# WinkBox Remote

An iPhone app for the Rostelecom WinkBox 2 (an Android TV box): a voice assistant for the TV, and a remote.

- **Voice.** Tap the orb and talk. The phone turns your speech into text (Apple's recognizer, on the iPhone itself for
  languages that support it) and sends only the words to the TV. The assistant on the TV decides what to do and does
  it: volume, playback, timers, opening apps, navigating. Short commands are handled on the TV in tens of
  milliseconds, with no cloud involved; anything more open-ended goes from the TV to Claude (Anthropic's API).
- **Remote.** An Apple-TV-style touch pad or arrows, the Siri Remote's buttons, a screen of big app tiles, and typing
  into the TV's search boxes. Buttons, typing and app launches go through the same paired connection, so this phone
  holds no shell-level access to the box.

Everything that thinks and acts runs on the TV (the WinkBox Assistant app, a foreground service on the box). No
computer is needed. The phone is the microphone and the screen.

## How the phone and the TV talk

A WebSocket on the TV's port 8731 (`ws://<tv>:8731/ws`), found over Bonjour as `_winkbox._tcp` on the home Wi-Fi.

- **Pairing.** Once, with a 6-digit code the TV shows on screen: P-256 key agreement, with both public keys and a nonce
  bound into an HMAC keyed by the code, then HKDF-SHA256 for the shared secret. Five wrong codes lock pairing for a
  minute. An unpaired phone can only ask to pair.
- **Every connection** starts with a challenge the TV sends and a MAC the phone answers with, so nothing secret is
  replayable.
- **The Anthropic API key** is typed into the app once and sent to the TV sealed (AES-256-GCM under a key derived from
  the pairing secret). The TV keeps it in the Android Keystore; the phone never stores it and nothing logs it.

## Building

The app is built without Xcode on the user's Mac: every push to `main` builds it on GitHub's Macs
(`.github/workflows/build.yml` runs `build.sh`) and publishes `WinkRemote.ipa` as the
[latest release](../../releases/tag/latest). If a build fails, its log is published as the
[build-log](../../releases/tag/build-log) release. `build.sh` can also build locally, either with Xcode or with the Mac's
Command Line Tools plus the iPhone SDK pulled out of an Xcode .xip by `Tools/extract-sdk.py`.

The build runs on GitHub's macOS 26 machines (Xcode 26, the iOS 26 SDK): on iOS 26 every glass surface (the keys, the tab bar,
the cards) is Apple's Liquid Glass and the Settings and History screens are the system's own grouped lists; on iOS 16 to 18 the
same screens fall back to frosted materials.

There are no image files: the app tiles are drawn in SwiftUI (`BrandArt` in `App/UI/AppsView.swift`) and the app icon is
drawn by `Tools/icon/main.swift` during the build. `Tools/preview` renders every screen on a Mac, in every state, to
check the design without a phone.

## Installing

Download `WinkRemote.ipa` from the latest release and install it with [Sideloadly](https://sideloadly.io), signed in
with your Apple ID (or with [xtool](https://github.com/xtool-org/xtool) on macOS 14 or later). An app signed with a
free Apple ID stops opening after 7 days; installing it again renews it.

The first time it opens, iOS asks for the local network, the microphone and speech recognition: allow all three.
Then: Settings (the gear) → Pairing → "Show a code on the TV", type the code, and paste your Anthropic API key under
"Anthropic API key" → "Save to TV".

## Layout

| | |
|---|---|
| `App/Core/Assistant.swift` | The assistant as the phone sees it: finds the TV, pairs, listens, sends, shows and speaks the answer |
| `App/Core/Speech.swift` | Microphone to text (Apple's recognizer, streaming partial results) and text to speech |
| `App/Core/WBCrypto.swift` | Pairing and sealed-settings cryptography, matching the TV's Java side; Keychain storage |
| `App/Core/TV.swift` | The box as the remote sees it: buttons, typing and app launches, relayed through the assistant |
| `App/Core/ADB.swift`, `ADBKey.swift` | The original direct connection to the box's network debugging; kept for reference, not used while paired |
| `App/UI/VoiceView.swift` | The voice screen: the orb and its states, the transcript, the answer, suggestions, history |
| `App/UI/AssistantSettings.swift` | Pairing, the API key, model and thinking effort, language, spoken replies |
| `App/UI/` (the rest) | Remote, apps, typing, settings, theme |
| `Tools/icon`, `Tools/preview` | Draws the app icon; renders the screens on a Mac |
