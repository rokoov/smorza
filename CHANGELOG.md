# Changelog

## 0.4.0 (not released yet)

New:

- A welcome window explains the one permission Smorza needs before macOS asks for it, helps when it was
  refused, and points to the menu bar icon. Settings can show it again.
- Actions for the Shortcuts app: Set App Volume, Mute App, Set App Output Device, Mute All Apps and Unmute All
  Apps. Spotlight and Siri offer them too.
- `smorza://` links for Terminal, Raycast and the Open URLs action in Shortcuts: set, step or mute an app's
  volume, send it to a device, Mute All, reset every app, or open the mixer.
- Shortcuts you record in Settings: open or close the mixer, also over a full-screen app, and turn the playing
  app up or down 5% or mute it. A held key repeats.
- Ignore an app from its row's menu: Smorza leaves its sound alone and stops listing it. Settings lists ignored
  apps.
- A Notifications & alerts row for the system's alert volume, which Settings can hide.
- The menu bar icon is crossed out while Mute All is on, and can show the output volume instead.
- Sliders in each app's colour, off by default.
- Liquid Glass on macOS 26 and later.
- German, French and Croatian.
- A first look at Smorza Pro in Settings.

Changed:

- The volume keys change the playing app, the one that started playing last, instead of the app in front,
  which is often silent. With nothing playing they still change the app in front.
- After a link or a closed Settings window, the keyboard goes back to the app you were in.

Fixed:

- The level line under a slider no longer runs through its knob.

## 0.3.0 (2026-11-20)

- A settings window behind the gear in the panel
- The volume keys can change the app in front; Option + the keys still change the Mac's volume
- Scroll over a row to change its volume, and move a focused slider with the arrow keys
- Pin an app to keep it in the list while it is quiet, so you can set it before it plays
- Mute All, from the panel or with Control-Option-M anywhere
- An output priority list: the first connected device becomes the output, and each device keeps its own volume
- A small overlay when the output changes

## 0.2.1 (2026-11-20)

The first release under the new name, Smorza (formerly Volume Mixer).

- An output device for each app: Spotify on the speakers, Discord in the AirPods
- Level meters under the apps that go through the mixer, while the panel is open
- Updates itself from now on: checks once a day and asks before installing
- Turned-down apps reach the speakers 10 ms sooner (12 ms instead of 23 ms)
- The app opens at once instead of waiting on macOS's audio service
- An aggregate device that includes a microphone works as an output
- Copy Diagnostics: right-click the version at the bottom of the panel

## 0.1.0 (2026-11-18)

The first release, as Volume Mixer.

- A slider and a mute button for every app that plays sound, the output volume, and the output device picker
- Helper processes fold into their app (Chrome, Safari, Discord)
- Volumes are remembered per app; apps at 100% are never touched
- Nothing is muted until a capture check proves macOS lets the mixer hear other apps
- Routes follow output device changes and recover after sleep and Core Audio restarts
