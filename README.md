# Volume Mixer

<img src="Resources/AppIcon-preview.png" width="96" align="right" alt="">

A free menu bar app that gives every Mac app its own volume slider and mute button, like the volume mixer on
Windows. Nothing to install besides the app: no audio driver, no kernel extension. It uses the Core Audio
process taps that macOS 14.4 and later provide.

- A slider and a mute button for each app that plays sound, and the output device's own volume on top
- An output device per app: Spotify on the speakers, Discord in the AirPods. Point at an app's row and pick the
  device from the button that appears next to its slider, or right-click the row. If the device goes away the app
  plays on the default output, and it moves back when the device returns
- Volumes are remembered per app and per device: 40% on the speakers, 100% in the headphones
- Level meters under the sliders of the apps that go through the mixer, while the panel is open
- Option-click an app's speaker to play it solo; Option-click again to bring the others back
- Control + volume keys change the app in front instead of the whole Mac, with a small overlay (needs the
  Accessibility permission, asked for when you turn it on)
- Browsers and Electron apps play sound from helper processes; those fold into their app (Chrome, Safari, Discord)
- Apps at 100% on the default output are never touched. Only apps you turn down, mute or send to another device
  go through the mixer
- Updates itself: checks once a day and asks before installing
- Universal app for Apple silicon and Intel Macs

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img src="docs/screenshot-light.png" width="376" alt="The Volume Mixer panel: output volume on top, a slider and mute button per app, and the output devices">
</picture>

## Install

Needs macOS 14.4 Sonoma or later.

1. Download `VolumeMixer-<version>.zip` from [Releases](../../releases), unzip it and move **VolumeMixer** to
   Applications.
2. Open it and click the sliders icon in the menu bar.
3. The first time you turn an app down, macOS asks to let Volume Mixer record system audio. Click **Allow**: that
   is how an app's sound reaches the mixer. Nothing is recorded or saved. The only network traffic is the daily
   update check, which reads the release feed on GitHub.

From 0.2.0 on the app updates itself. A copy of 0.1.0 has to be replaced by hand once.

<details>
<summary>macOS says it cannot check the app for malware</summary>

That copy is not notarized by Apple: releases before 0.2.0 and builds you make yourself are signed ad hoc. Click
**Done**, then open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to
Volume Mixer. If you prefer the terminal: `xattr -dr com.apple.quarantine /Applications/VolumeMixer.app`

</details>

If you clicked Don't Allow, turn Volume Mixer on under **System Settings → Privacy & Security → Screen & System
Audio Recording → System Audio Recording Only** and press **Try Again** in the panel. Until then every app plays
at full volume.

## Build from source

Needs macOS 14.4 or later and Swift 5.9 or later. The Command Line Tools are enough (`xcode-select --install`).
The first build fetches [Sparkle](https://sparkle-project.org) through SwiftPM.

```sh
scripts/build.sh            # builds build/VolumeMixer.app for this Mac
scripts/build.sh run        # builds and launches it
scripts/build.sh install    # copies it to /Applications and launches it
scripts/format.sh           # formats the code with swift-format
scripts/check.sh            # formatting, build without warnings, core checks, bundle checks
scripts/release.sh          # universal app zipped for a release
scripts/appcast.sh <zip>    # signs a release zip and adds it to the update feed
```

The code follows the formatting of Apple's SwiftNIO (`.swift-format`): `scripts/format.sh` applies it and
`scripts/check.sh` fails on anything it would change. Signing, notarizing and publishing a release is described in
[docs/RELEASING.md](docs/RELEASING.md).

## How it works

For each app below 100% the mixer creates a muted process tap, which takes the app's audio before it reaches the
speakers, and a private aggregate device that holds the tap and the real output device. The aggregate device's
IO callback plays the tapped audio at the app's volume. Taps and aggregate devices belong to the mixer, so if it
quits or crashes macOS removes them and every app plays normally again.

A denied permission gives no error, only silence, so before muting anything the mixer plays an inaudible signal
and listens for it through a tap of its own process. Only when it hears it are apps routed.

To name helper processes after their app, the mixer asks macOS which app is responsible for them
(`responsibility_get_pid_responsible_for_pid`, a private call that has been stable for years). If it ever
disappears, helpers show under their own names.

| Path | What |
| --- | --- |
| `Sources/MixerCore` | Pure logic: real-time renderer, volume curve, saved settings, row order |
| `Sources/VolumeMixer/CoreAudio` | Audio clients, process taps, the capture check, output devices |
| `Sources/VolumeMixer/Mixer` | `MixerModel`, `RouteManager` and `CaptureCheckController`: what is routed, when and where |
| `Sources/VolumeMixer/Views` | The menu bar panel, one view per file |
| `Sources/VolumeMixer/App` | Entry point, app delegate, login item, updates, logging |
| `Checks/MixerCoreChecks` | Checks for `MixerCore`, run by `scripts/check.sh` |

## Known issues

- A turned-down app that was idle starts a few milliseconds late when it plays again
- An app sent to a device in the mixer plays there even if the app picked another device in its own settings;
  one left on the system default but turned down follows the system default the same way
- Other audio routing tools (Background Music, SoundSource, Loopback) can fight over the same apps
- Builds you make yourself are signed ad hoc, so macOS may ask for the permissions again after each build

## Roadmap

The mixer stays free. Next for everyone: scroll over a row to change its volume, pinned apps, mute all, an output
priority list and a small settings window.

Pro, coming soon, a one-time unlock for automation:

- Call ducking: other apps turn down while you are in a call
- Global microphone mute with a menu bar indicator
- Profiles: save a mix and switch by shortcut, when a device connects or when an app launches
- Boost quiet apps up to 200%, with a limiter so nothing clips
- Night mode: a gentle compressor on every app for late-night listening
- A command palette: type "spotify 30" or "discord to airpods"
- Shortcuts actions and a URL scheme for scripts

## Uninstall

Quit Volume Mixer from its panel, delete it from Applications and, if you like, remove its permission:
`tccutil reset AudioCapture com.rokoov.volumemixer`

## Debugging

```sh
/Applications/VolumeMixer.app/Contents/MacOS/VolumeMixer --list            # audio clients and output devices
/Applications/VolumeMixer.app/Contents/MacOS/VolumeMixer --snapshot /tmp   # panel rendered to PNG, routing off
/usr/bin/log stream --predicate 'subsystem == "com.rokoov.volumemixer"'
```

`--snapshot-demo <dir>` renders the panel with sample apps and devices; it made the screenshots above.

## License

MIT, see [LICENSE](LICENSE).
