import CoreAudio
import Foundation
import MixerCore

setvbuf(stdout, nil, _IONBF, 0)

var failures = 0
var passed = 0

func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

func nearlyEqual(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 1e-5 }

/// An AudioBufferList whose buffers own their sample memory, freed by `release`.
struct TestBuffers {
    let list: UnsafeMutableAudioBufferListPointer
    let storage: [UnsafeMutablePointer<Float>]

    init(
        channelsPerBuffer: [Int],
        frames: Int,
        fill: (_ buffer: Int, _ frame: Int, _ channel: Int) -> Float = { _, _, _ in 0 }
    ) {
        // allocate traps on zero buffers, so an empty list is one slot with a count of zero.
        list = AudioBufferList.allocate(maximumBuffers: max(1, channelsPerBuffer.count))
        list.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(channelsPerBuffer.count)
        var storage: [UnsafeMutablePointer<Float>] = []
        for (index, channels) in channelsPerBuffer.enumerated() {
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: max(1, frames * channels))
            for frame in 0..<frames {
                for channel in 0..<channels {
                    samples[frame * channels + channel] = fill(index, frame, channel)
                }
            }
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(channels),
                mDataByteSize: UInt32(frames * channels * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(samples)
            )
            storage.append(samples)
        }
        self.storage = storage
    }

    func sample(buffer: Int, frame: Int, channel: Int) -> Float {
        storage[buffer][frame * Int(list[buffer].mNumberChannels) + channel]
    }

    func release() {
        for samples in storage {
            samples.deallocate()
        }
        free(list.unsafeMutablePointer)
    }
}

func stereoTap(frames: Int) -> TestBuffers {
    TestBuffers(channelsPerBuffer: [2], frames: frames) { _, frame, channel in
        channel == 0 ? Float(frame + 1) * 0.01 : -Float(frame + 1) * 0.02
    }
}

func run(_ renderer: TapRenderer, input: TestBuffers, output: TestBuffers) {
    renderer.render(input: UnsafePointer(input.list.unsafeMutablePointer), output: output.list.unsafeMutablePointer)
}

// Stereo tap into an interleaved stereo device at a steady gain.
do {
    let frames = 16
    let input = stereoTap(frames: frames)
    let output = TestBuffers(channelsPerBuffer: [2], frames: frames, fill: { _, _, _ in 9 })
    let renderer = TapRenderer(tapBufferIndex: 0, gain: 0.5)
    run(renderer, input: input, output: output)
    var matches = true
    for frame in 0..<frames {
        matches =
            matches
            && nearlyEqual(
                output.sample(buffer: 0, frame: frame, channel: 0),
                input.sample(buffer: 0, frame: frame, channel: 0) * 0.5
            )
            && nearlyEqual(
                output.sample(buffer: 0, frame: frame, channel: 1),
                input.sample(buffer: 0, frame: frame, channel: 1) * 0.5
            )
    }
    expect(matches, "stereo output is the tap scaled by the gain")
    expect(nearlyEqual(renderer.takePeak(), Float(frames) * 0.02), "peak is the loudest tap sample")
    expect(renderer.takePeak() == 0, "peak resets after it is read")
    input.release()
    output.release()
}

// A gain change ramps across one buffer and then holds.
do {
    let frames = 8
    let input = TestBuffers(channelsPerBuffer: [2], frames: frames) { _, _, _ in 1 }
    let output = TestBuffers(channelsPerBuffer: [2], frames: frames)
    let renderer = TapRenderer(tapBufferIndex: 0, gain: 1)
    renderer.gain = 0
    run(renderer, input: input, output: output)
    expect(
        nearlyEqual(output.sample(buffer: 0, frame: 0, channel: 0), 1 - 1 / Float(frames)),
        "ramp starts just below the old gain"
    )
    expect(nearlyEqual(output.sample(buffer: 0, frame: frames - 1, channel: 1), 0), "ramp ends on the new gain")
    run(renderer, input: input, output: output)
    expect(nearlyEqual(output.sample(buffer: 0, frame: 0, channel: 0), 0), "the next buffer holds the new gain")
    renderer.gain = -3
    expect(renderer.gain == 0, "a negative gain clamps to silence")
    input.release()
    output.release()
}

// A headset's microphone stream comes before the tap; the renderer must skip it.
do {
    let frames = 4
    let input = TestBuffers(channelsPerBuffer: [1, 2], frames: frames) { buffer, _, channel in
        buffer == 0 ? 0.9 : (channel == 0 ? 0.25 : 0.75)
    }
    let output = TestBuffers(channelsPerBuffer: [2], frames: frames)
    run(TapRenderer(tapBufferIndex: 1, gain: 1), input: input, output: output)
    expect(
        nearlyEqual(output.sample(buffer: 0, frame: 2, channel: 0), 0.25),
        "left comes from the tap, not the microphone"
    )
    expect(nearlyEqual(output.sample(buffer: 0, frame: 2, channel: 1), 0.75), "right comes from the tap")
    input.release()
    output.release()
}

// Mono, split and multichannel devices.
do {
    let frames = 4
    let input = TestBuffers(channelsPerBuffer: [2], frames: frames) { _, _, channel in channel == 0 ? 0.2 : 0.6 }

    let mono = TestBuffers(channelsPerBuffer: [1], frames: frames)
    run(TapRenderer(tapBufferIndex: 0, gain: 1), input: input, output: mono)
    expect(
        nearlyEqual(mono.sample(buffer: 0, frame: 1, channel: 0), 0.4),
        "a mono device gets the average of both sides"
    )

    let split = TestBuffers(channelsPerBuffer: [1, 1], frames: frames)
    run(TapRenderer(tapBufferIndex: 0, gain: 1), input: input, output: split)
    expect(
        nearlyEqual(split.sample(buffer: 0, frame: 3, channel: 0), 0.2),
        "non-interleaved device: first buffer is left"
    )
    expect(
        nearlyEqual(split.sample(buffer: 1, frame: 3, channel: 0), 0.6),
        "non-interleaved device: second buffer is right"
    )

    let surround = TestBuffers(channelsPerBuffer: [4, 2], frames: frames, fill: { _, _, _ in 5 })
    run(TapRenderer(tapBufferIndex: 0, gain: 1), input: input, output: surround)
    expect(
        nearlyEqual(surround.sample(buffer: 0, frame: 0, channel: 1), 0.6),
        "multichannel device: channel 2 is right"
    )
    expect(surround.sample(buffer: 0, frame: 0, channel: 3) == 0, "multichannel device: extra channels are silent")
    expect(surround.sample(buffer: 1, frame: 0, channel: 0) == 0, "multichannel device: later streams are silent")

    for buffers in [input, mono, split, surround] {
        buffers.release()
    }
}

// No input at all writes silence instead of leaving stale samples.
do {
    let input = TestBuffers(channelsPerBuffer: [], frames: 4)
    let output = TestBuffers(channelsPerBuffer: [2], frames: 4, fill: { _, _, _ in 7 })
    run(TapRenderer(tapBufferIndex: 0, gain: 1), input: input, output: output)
    expect(output.sample(buffer: 0, frame: 3, channel: 1) == 0, "missing tap input renders silence")
    input.release()
    output.release()
}

// Limiter: boost never pushes a sample past the ceiling, and quiet audio passes untouched.
do {
    let frames = 4_800
    let loud = TestBuffers(channelsPerBuffer: [2], frames: frames) { _, frame, _ in frame % 2 == 0 ? 0.8 : -0.8 }
    let output = TestBuffers(channelsPerBuffer: [2], frames: frames)
    let renderer = TapRenderer(tapBufferIndex: 0, gain: 2)
    run(renderer, input: loud, output: output)
    var loudest: Float = 0
    for frame in 0..<frames {
        loudest = max(loudest, abs(output.sample(buffer: 0, frame: frame, channel: 0)))
    }
    expect(loudest <= TapRenderer.ceiling + 1e-6, "a 0.8 signal boosted twice stays under the ceiling: \(loudest)")
    expect(
        loudest > TapRenderer.ceiling - 0.01,
        "the limiter holds the signal at the ceiling, not below it: \(loudest)"
    )

    let quiet = TestBuffers(channelsPerBuffer: [2], frames: frames) { _, _, _ in 0.3 }
    let recovering = TapRenderer(tapBufferIndex: 0, gain: 2)
    run(recovering, input: loud, output: output)
    for _ in 0..<10 {
        run(recovering, input: quiet, output: output)
    }
    let settled = output.sample(buffer: 0, frame: frames - 1, channel: 1)
    expect(nearlyEqual(settled, 0.6), "after the peak the limiter lets go and 0.3 boosted twice is 0.6: \(settled)")

    let untouched = TapRenderer(tapBufferIndex: 0, gain: 1)
    run(untouched, input: quiet, output: output)
    expect(output.sample(buffer: 0, frame: 7, channel: 0) == 0.3, "quiet audio at 100% passes bit for bit")
    for buffers in [loud, output, quiet] {
        buffers.release()
    }
}

// Volume curve.
expect(VolumeCurve.gain(volume: 1, isMuted: false) == 1, "100% is unity gain")
expect(VolumeCurve.gain(volume: 0.999, isMuted: false) == 1, "a hair under 100% is still unity gain")
expect(nearlyEqual(VolumeCurve.gain(volume: 0.5, isMuted: false), 0.25), "50% is a quarter of the amplitude")
expect(nearlyEqual(VolumeCurve.gain(volume: 1.5, isMuted: false), 1.5), "boost is linear: 150% is 1.5 times the signal")
expect(VolumeCurve.gain(volume: 3, isMuted: false) == 2, "boost stops at 200%")
expect(VolumeCurve.gain(volume: 0.8, isMuted: true) == 0, "muted is silent")
expect(VolumeCurve.gain(volume: -1, isMuted: false) == 0, "volume clamps below zero")
expect(VolumeCurve.percent(0.996) == 100, "percent rounds to the label the user sees")
expect(VolumeCurve.percent(1.5) == 150, "boost reads above 100%")

// Slider positions: 100% sits three quarters along, boost takes the last quarter.
expect(VolumeScale.boosted.position(of: 1) == VolumeScale.boosted.unityPosition, "100% sits on the mark")
expect(VolumeScale.boosted.position(of: 2) == 1, "200% is the end of the slider")
expect(nearlyEqual(Float(VolumeScale.boosted.position(of: 0.5)), 0.375), "50% is half way to the mark")
expect(
    VolumeScale.boosted.volume(atPosition: VolumeScale.boosted.unityPosition + 0.01) == 1,
    "a drag next to the mark snaps onto 100%"
)
expect(
    nearlyEqual(Float(VolumeScale.boosted.volume(atPosition: 0.875)), 1.5),
    "half way through the boost quarter is 150%"
)
for volume in [0.0, 0.2, 0.6, 1.3, 1.8, 2.0] {
    let roundTrip = VolumeScale.boosted.volume(atPosition: VolumeScale.boosted.position(of: volume))
    expect(nearlyEqual(Float(roundTrip), Float(volume)), "position and volume convert both ways for \(volume)")
}
expect(AppVolume(volume: 1.4).isBoosted, "above 100% is boost")
expect(AppVolume(volume: 1.4).needsRouting, "a boosted app is routed")
expect(AppVolume(volume: 0.4).needsRouting, "a quieter app is routed")

// Settings: version 1 migrates, volumes are kept per device, devices are remembered, apps back at
// default are forgotten, and a newer format on disk is never overwritten.
do {
    let suiteName = "MixerCoreChecks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else { fatalError("no defaults suite") }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let legacy = try JSONEncoder().encode(["com.spotify.client": AppVolume(volume: 0.3)])
    defaults.set(legacy, forKey: "AppVolumes")

    let store = MixerSettingsStore(defaults: defaults)
    expect(
        store.volume(for: "com.spotify.client", on: "speakers") == AppVolume(volume: 0.3),
        "a version 1 volume carries over to any device"
    )
    store.adoptVolume(for: "com.spotify.client", on: "speakers")
    store.setVolume(AppVolume(volume: 1), for: "com.spotify.client", on: "headphones")
    expect(store.volume(for: "com.spotify.client", on: "speakers").volume == 0.3, "speakers keep their own volume")
    expect(store.volume(for: "com.spotify.client", on: "headphones").volume == 1, "headphones get theirs")
    expect(store.volume(for: "com.spotify.client", on: "tv").volume == 1, "a new device starts at the last volume")

    store.setOutputDevice(uid: "airpods", name: "AirPods Pro", for: "com.hnc.Discord")
    let reloaded = MixerSettingsStore(defaults: defaults)
    expect(
        reloaded.settings(for: "com.hnc.Discord").outputDeviceUID == "airpods",
        "a chosen device survives a relaunch"
    )
    expect(reloaded.volume(for: "com.spotify.client", on: "speakers").volume == 0.3, "per-device volumes survive too")

    reloaded.setOutputDevice(uid: nil, name: nil, for: "com.hnc.Discord")
    expect(!reloaded.appKeys.contains("com.hnc.Discord"), "an app back at default is forgotten")
    expect(reloaded.settings(for: "unknown.app") == AppSettings(), "an unknown app starts at default")

    let newer = Data(#"{"version":99,"apps":{}}"#.utf8)
    defaults.set(newer, forKey: "Settings")
    MixerSettingsStore(defaults: defaults).setVolume(AppVolume(volume: 0.5), for: "x", on: "y")
    expect(defaults.data(forKey: "Settings") == newer, "a newer settings format is left untouched")
}

// Row order: playing apps first, then pinned, then by when they last played; open panels keep rows
// in place.
struct Row: MixerRowItem {
    let id: String
    let isPlaying: Bool
    var isPinned = false
    var name: String { id }
}

do {
    let rows = [
        Row(id: "zoom", isPlaying: false),
        Row(id: "Spotify", isPlaying: true),
        Row(id: "chrome", isPlaying: true),
        Row(id: "Discord", isPlaying: false),
    ]
    let arranged = RowOrder.arrange(rows).map(\.id)
    expect(
        arranged == ["chrome", "Spotify", "Discord", "zoom"],
        "playing first, then names ignoring case: \(arranged)"
    )

    let onScreen = ["Discord", "chrome", "gone"]
    let held = RowOrder.arrange(rows, keepingPlacesOf: onScreen).map(\.id)
    expect(
        held == ["Discord", "chrome", "Spotify", "zoom"],
        "rows on screen hold their places, new ones follow: \(held)"
    )
    expect(RowOrder.arrange([Row]()).isEmpty, "no rows stays no rows")

    let now = Date()
    let mixed = [
        Row(id: "zoom", isPlaying: false, isPinned: true),
        Row(id: "Discord", isPlaying: false),
        Row(id: "Music", isPlaying: false),
        Row(id: "Spotify", isPlaying: true),
        Row(id: "Arc", isPlaying: false),
        Row(id: "Slack", isPlaying: true, isPinned: true),
    ]
    let recent = RowOrder.arrange(
        mixed,
        lastPlayed: ["Music": now, "Discord": now.addingTimeInterval(-60), "zoom": now.addingTimeInterval(-5)]
    ).map(\.id)
    expect(
        recent == ["Slack", "Spotify", "zoom", "Music", "Discord", "Arc"],
        "playing, then pinned, then most recently played, then never played: \(recent)"
    )
}

// Mute All: every app muted, and each app's own mute back afterwards.
do {
    let session = MuteAllSession(mutesBefore: ["spotify": false, "zoom": true])
    expect(session.mutes == ["spotify": true, "zoom": true], "every app is muted")
    expect(session.mutesBefore["zoom"] == true, "an app muted before stays muted after")
    expect(MuteAllSession(mutesBefore: [:]).mutes.isEmpty, "with no apps there is nothing to mute")
}

// Output priority: the first connected device in the user's order, each device with its volume.
do {
    var priority = OutputPriority()
    let speakers = OutputPriority.Device(uid: "speakers", name: "Speakers")
    let airpods = OutputPriority.Device(uid: "airpods", name: "AirPods Pro")
    let display = OutputPriority.Device(uid: "display", name: "Studio Display")
    expect(priority.learn([speakers, airpods]), "new devices are learned")
    expect(priority.preferredDevice(among: ["speakers", "airpods"]) == nil, "nothing switches while it is off")
    priority.isEnabled = true
    expect(priority.preferredDevice(among: ["speakers", "airpods"]) == "speakers", "the first in the list wins")
    priority.move("airpods", by: -1)
    expect(priority.devices.map(\.uid) == ["airpods", "speakers"], "a device moves up")
    expect(priority.preferredDevice(among: ["speakers", "airpods"]) == "airpods", "and now wins")
    expect(priority.preferredDevice(among: ["speakers"]) == "speakers", "until it is unplugged")
    expect(priority.preferredDevice(among: ["usb"]) == nil, "an unlisted device is left to macOS")
    priority.move("airpods", by: -5)
    expect(priority.devices.first?.uid == "airpods", "moving past the top stops there")
    expect(priority.learn([display]), "a new device joins")
    expect(priority.devices.last?.uid == "display", "at the end")
    expect(!priority.learn([airpods]), "a known device changes nothing")
    priority.learn([OutputPriority.Device(uid: "airpods", name: "Roko's AirPods")])
    expect(priority.devices.first?.name == "Roko's AirPods", "a renamed device keeps its place")
    priority.volumes["display"] = 0.3
    priority.forget("display")
    expect(priority.devices.count == 2 && priority.volumes["display"] == nil, "a forgotten device goes with its volume")

    let defaults = UserDefaults(suiteName: "priority-check")!
    defaults.removePersistentDomain(forName: "priority-check")
    let store = MixerSettingsStore(defaults: defaults)
    store.setOutputPriority(priority)
    expect(MixerSettingsStore(defaults: defaults).outputPriority == priority, "the order is saved and loads again")
    let version3 = #"{"version":3,"apps":{},"profiles":[]}"#
    defaults.set(Data(version3.utf8), forKey: "Settings")
    expect(
        MixerSettingsStore(defaults: defaults).outputPriority == OutputPriority(),
        "a version 3 save loads with it off"
    )
    defaults.removePersistentDomain(forName: "priority-check")
}

// Pins: a pinned app is kept even at 100% on the system output, and old saves load unpinned.
do {
    expect(!AppSettings(isPinned: true).isDefault, "a pinned app is worth keeping")
    let old = Data(#"{"volumes":{},"lastVolume":{"volume":0.5,"isMuted":false}}"#.utf8)
    let decoded = try? JSONDecoder().decode(AppSettings.self, from: old)
    expect(decoded?.isPinned == false, "a save from before pins loads unpinned")
    let defaults = UserDefaults(suiteName: "pins-check")!
    defaults.removePersistentDomain(forName: "pins-check")
    let store = MixerSettingsStore(defaults: defaults)
    store.setPinned(true, for: "us.zoom.xos")
    expect(store.pinnedApps == ["us.zoom.xos"], "a pin is saved")
    expect(MixerSettingsStore(defaults: defaults).pinnedApps == ["us.zoom.xos"], "and loads again")
    store.setPinned(false, for: "us.zoom.xos")
    expect(store.pinnedApps.isEmpty, "unpinning an untouched app forgets it")
    defaults.removePersistentDomain(forName: "pins-check")
}

// Solo: everyone else muted, and each app's own mute back afterwards.
do {
    let session = SoloSession(key: "spotify", mutesBefore: ["spotify": true, "chrome": false, "discord": true])
    expect(
        session.mutes == ["spotify": false, "chrome": true, "discord": true],
        "solo mutes the others and unmutes itself"
    )
    expect(session.mutesBefore["discord"] == true, "an app muted before the solo stays muted after it")
    expect(
        SoloSession(key: "a", mutesBefore: [:]).mutes == ["a": false],
        "a solo with nothing else listed mutes nothing"
    )
}

// Profiles: listed apps take the profile's values, others are muted only when the profile says so,
// and profiles survive a relaunch next to a version 2 save.
do {
    let meeting = Profile(name: "Meeting", apps: ["zoom": AppVolume(volume: 1.2)], mutesOtherApps: true)
    let current = ["zoom": AppVolume(volume: 0.5), "spotify": AppVolume(volume: 0.7)]
    let changes = meeting.changes(from: current)
    expect(changes["zoom"] == AppVolume(volume: 1.2), "a listed app takes the profile's volume")
    expect(changes["spotify"] == AppVolume(volume: 0.7, isMuted: true), "an app left out is muted, its volume kept")
    var gentle = meeting
    gentle.mutesOtherApps = false
    expect(gentle.changes(from: current)["spotify"] == nil, "without muting others, apps left out are untouched")
    let away = Profile(name: "Away", apps: ["discord": AppVolume(isMuted: true)])
    expect(away.changes(from: current)["discord"]?.isMuted == true, "a listed app that is not running is still set")

    let suiteName = "MixerCoreChecks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else { fatalError("no defaults suite") }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let version2 = #"{"version":2,"apps":{"spotify":{"volumes":{},"lastVolume":{"volume":0.4,"isMuted":false}}}}"#
    defaults.set(Data(version2.utf8), forKey: "Settings")
    let store = MixerSettingsStore(defaults: defaults)
    expect(store.volume(for: "spotify", on: "x").volume == 0.4, "a version 2 save loads into the current one")
    expect(store.profiles.isEmpty, "a version 2 save has no profiles")
    store.saveProfile(meeting)
    var renamed = meeting
    renamed.name = "Calls"
    store.saveProfile(renamed)
    let reloaded = MixerSettingsStore(defaults: defaults)
    expect(reloaded.profiles == [renamed], "a profile saved again replaces itself and survives a relaunch")
    reloaded.deleteProfile(id: meeting.id)
    expect(MixerSettingsStore(defaults: defaults).profiles.isEmpty, "a deleted profile stays deleted")
}

// Volume keys: sixteen steps with 100% on the twelfth, boost beyond, fine steps that can leave 100%.
do {
    var volume = 0.0
    for _ in 0..<12 {
        volume = VolumeScale.boosted.stepped(volume, by: 1, fine: false)
    }
    expect(nearlyEqual(Float(volume), 1), "twelve presses up from silence land on 100%: \(volume)")
    expect(nearlyEqual(Float(VolumeScale.boosted.stepped(1, by: 1, fine: false)), 1.25), "one press past 100% is 125%")
    expect(VolumeScale.boosted.stepped(2, by: 1, fine: false) == 2, "presses stop at 200%")
    expect(VolumeScale.boosted.stepped(0, by: -1, fine: false) == 0, "presses stop at silence")
    expect(VolumeScale.boosted.stepped(1, by: 1, fine: true) > 1, "a fine step up leaves 100% instead of snapping back")
    let fromDrag = VolumeScale.boosted.stepped(0.51, by: 1, fine: false)
    expect(
        nearlyEqual(Float(VolumeScale.boosted.position(of: fromDrag)), 7.0 / 16),
        "a dragged volume steps onto the grid"
    )
}

// The free scale ends at 100%: the slider is the volume, sixteen key steps reach the top.
do {
    let free = VolumeScale.standard
    expect(!free.allowsBoost && VolumeScale.boosted.allowsBoost, "only the boosted scale goes past 100%")
    expect(free.position(of: 0.4) == 0.4 && free.volume(atPosition: 0.4) == 0.4, "on the free scale position is volume")
    expect(free.clamped(1.6) == 1, "a boost saved under Pro plays at 100% on the free scale")
    expect(free.volume(atPosition: 0.99) == 1, "a drag near the end lands on 100%")
    var volume = 0.0
    for _ in 0..<16 {
        volume = free.stepped(volume, by: 1, fine: false)
    }
    expect(nearlyEqual(Float(volume), 1), "sixteen presses up reach 100%: \(volume)")
    expect(free.stepped(1, by: 1, fine: false) == 1, "presses stop at 100% without boost")
}

// Per-app output: older saves decode, and the routing rule covers volume, mute and device.
do {
    let decoder = JSONDecoder()
    let beforeDevices = try decoder.decode(
        AppSettings.self,
        from: Data(#"{"volumes":{"speakers":{"volume":0.4,"isMuted":false}}}"#.utf8)
    )
    expect(beforeDevices.outputDeviceUID == nil, "a save from before per-app output follows the system output")
    expect(beforeDevices.volume(on: "speakers").volume == 0.4, "its volumes still load")
    let bare = try decoder.decode(AppSettings.self, from: Data(#"{"lastVolume":{"volume":0.7,"isMuted":true}}"#.utf8))
    expect(bare.volumes.isEmpty && bare.lastVolume?.isMuted == true, "a save without per-device volumes loads too")

    let connected: Set = ["speakers", "airpods"]
    func routes(_ settings: AppSettings, system: String = "speakers", on devices: Set<String> = connected) -> Bool {
        settings.needsRoute(systemOutputUID: system, connectedUIDs: devices, scale: .standard)
    }
    expect(!routes(AppSettings()), "an untouched app plays directly")
    expect(routes(AppSettings(lastVolume: AppVolume(volume: 0.5))), "a turned-down app is routed")
    expect(routes(AppSettings(lastVolume: AppVolume(isMuted: true))), "a muted app is routed")
    let sent = AppSettings(outputDeviceUID: "airpods", outputDeviceName: "AirPods Pro")
    expect(routes(sent), "an app sent to another device is routed even at 100%")
    expect(!routes(sent, system: "airpods"), "sent to the system output itself, it plays untouched")
    expect(!routes(sent, on: ["speakers"]), "with its device unplugged it falls back and plays untouched")
    expect(
        sent.outputDeviceUID(systemOutputUID: "speakers", connectedUIDs: ["speakers"]) == "speakers",
        "an unplugged device sends the app to the system output"
    )
    expect(!routes(AppSettings(lastVolume: AppVolume(volume: 1.5))), "a Pro boost plays untouched on the free scale")
    expect(!sent.isDefault, "a chosen device is worth keeping even at 100%")
}

// Level meters: a decibel bar that rises at once and falls back gently.
do {
    expect(LevelMeter.fraction(ofPeak: 1) == 1, "full scale fills the bar")
    expect(LevelMeter.fraction(ofPeak: 2) == 1, "a peak over full scale still fills it, no more")
    expect(LevelMeter.fraction(ofPeak: 0) == 0, "silence is an empty bar")
    expect(LevelMeter.fraction(ofPeak: 0.0005) == 0, "under -60 dB is empty")
    expect(nearlyEqual(LevelMeter.fraction(ofPeak: 0.031_622_8), 0.5), "-30 dB is half the bar")
    expect(LevelMeter.next(from: 0.2, toward: 0.9) == 0.9, "a louder peak shows at once")
    expect(nearlyEqual(LevelMeter.next(from: 0.9, toward: 0), 0.84), "a bar falls one step per update")
    expect(LevelMeter.next(from: 0.03, toward: 0) == 0, "and stops at the new level, never below it")
}

// Scrolling over a row: up or right turns the volume up, whatever the scroll direction setting.
do {
    func change(x: Double = 0, y: Double = 0, precise: Bool = true, inverted: Bool = false) -> Double {
        ScrollStep.positionChange(deltaX: x, deltaY: y, isPrecise: precise, isInverted: inverted)
    }
    expect(change(y: 1, precise: false) == 0.05, "one wheel notch up is 5% more")
    expect(change(y: -1, precise: false) == -0.05, "one notch down is 5% less")
    expect(change(y: 10, precise: false) == ScrollStep.maximum, "an accelerated wheel moves at most 10% at once")
    expect(change(y: 20) > 0, "fingers up with classic scrolling turns it up")
    expect(change(y: -20, inverted: true) > 0, "fingers up with natural scrolling turns it up too")
    expect(change(x: -20) > 0, "fingers to the right with classic scrolling turn it up")
    expect(change(x: 20, inverted: true) > 0, "fingers to the right with natural scrolling turn it up too")
    expect(abs(change(y: 20) - 0.1) < 1e-9, "20 points of trackpad are 10%")
    expect(change(x: 1, y: 5) == change(y: 5), "the larger of the two directions decides")
    expect(ScrollStep.keyChange(isUp: true, isFine: false) == 0.05, "an arrow key moves 5%")
    expect(ScrollStep.keyChange(isUp: false, isFine: true) == -0.01, "with Shift it moves 1%")
}

// Icon tint: the most common saturated colour of an icon, readable in both appearances.
do {
    func pixels(_ colors: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
        colors.flatMap { [$0.0, $0.1, $0.2, $0.3] }
    }
    func icon(_ color: (UInt8, UInt8, UInt8), count: Int) -> [(UInt8, UInt8, UInt8, UInt8)] {
        Array(repeating: (color.0, color.1, color.2, 255), count: count)
    }
    let spotify = IconTint.dominant(rgba: pixels(icon((30, 215, 96), count: 80) + icon((0, 0, 0), count: 20)))
    expect(spotify.map { $0.green > $0.red && $0.green > $0.blue } == true, "a green icon gives green")
    let mixed = IconTint.dominant(rgba: pixels(icon((20, 90, 230), count: 60) + icon((230, 40, 40), count: 30)))
    expect(mixed.map { $0.blue > $0.red } == true, "the colour covering more of the icon wins")
    expect(IconTint.dominant(rgba: pixels(icon((128, 128, 128), count: 100))) == nil, "a grey icon keeps the accent")
    expect(
        IconTint.dominant(rgba: pixels(icon((255, 0, 0), count: 1) + icon((200, 200, 200), count: 99))) == nil,
        "a speck of colour is not enough"
    )
    let transparent = Array(repeating: (UInt8(255), UInt8(0), UInt8(0), UInt8(0)), count: 100)
    expect(IconTint.dominant(rgba: pixels(transparent)) == nil, "transparent pixels count for nothing")
    if let yellow = IconTint.dominant(rgba: pixels(icon((255, 240, 60), count: 100))) {
        expect(max(yellow.red, yellow.green, yellow.blue) <= 0.85 + 1e-9, "a light yellow is darkened to stay readable")
    } else {
        expect(false, "a yellow icon gives a colour")
    }
}

// Links: each smorza:// action with its parameters; anything else is turned away with a reason.
do {
    func command(_ link: String) -> URLCommand? {
        guard let url = URL(string: link) else { return nil }
        return try? URLCommand.parse(url).get()
    }
    expect(
        command("smorza://set-volume?app=com.spotify.client&volume=40")
            == .setVolume(apps: ["com.spotify.client"], percent: 40),
        "set-volume names an app and a volume"
    )
    expect(
        command("smorza://set-volume?app=a&app=b&app=A&volume=0") == .setVolume(apps: ["a", "b"], percent: 0),
        "several apps, each once"
    )
    expect(command("smorza://set-volume?app=a&volume=101") == nil, "a volume over 100 is turned away")
    expect(command("smorza://set-volume?app=a&volume=nan") == nil, "so is one that is not a number")
    expect(command("smorza://set-volume?app=a&volume=10&volume=20") == nil, "and a volume given twice")
    expect(command("smorza://set-volume?volume=50") == nil, "an app is needed")
    expect(command("smorza://step-volume?app=a&direction=up") == .stepVolume(apps: ["a"], direction: 1), "step up")
    expect(command("smorza://step-volume?app=a&direction=Down") == .stepVolume(apps: ["a"], direction: -1), "step down")
    expect(command("smorza://step-volume?app=a&direction=sideways") == nil, "an unknown direction")
    expect(command("smorza://mute?app=a&muted=true") == .mute(apps: ["a"], change: .mute), "mute")
    expect(command("smorza://mute?app=a&muted=false") == .mute(apps: ["a"], change: .unmute), "unmute")
    expect(command("smorza://mute?app=a") == .mute(apps: ["a"], change: .toggle), "a bare mute toggles")
    expect(command("smorza://mute?app=a&muted=maybe") == nil, "an unknown mute")
    expect(
        command("smorza://set-output?app=a&device=AirPods+Pro") == .setOutput(apps: ["a"], device: "AirPods Pro"),
        "a plus in a device name is a space"
    )
    expect(
        command("smorza://set-output?app=a&device=Desk%20%2B%20Sub") == .setOutput(apps: ["a"], device: "Desk + Sub"),
        "and %2B a plus"
    )
    expect(command("smorza://set-output?app=a") == nil, "set-output needs a device")
    expect(command("smorza://mute-all?muted=toggle") == .muteAll(.toggle), "mute-all")
    expect(command("smorza://reset") == .reset, "reset")
    expect(
        command("smorza://open") == .open && command("smorza://") == .open && command("SMORZA://Open/") == .open,
        "open, also with nothing after the scheme"
    )
    expect(command("smorza://explode") == nil, "an unknown action")
    expect(command("https://open") == nil, "another scheme")
    let rejection = URL(string: "smorza://set-volume?app=a&volume=loud").map(URLCommand.parse)
    expect(
        rejection.map { if case .failure(let reason) = $0 { reason.description.contains("loud") } else { false } }
            == true,
        "the reason names what was wrong"
    )
}

// Mute changes, and the 5% steps of the shortcuts and links.
do {
    expect(MuteChange.mute.applied(to: false) && MuteChange.mute.applied(to: true), "mute mutes")
    expect(!MuteChange.unmute.applied(to: true), "unmute unmutes")
    expect(MuteChange.toggle.applied(to: false) && !MuteChange.toggle.applied(to: true), "toggle flips")
    let free = VolumeScale.standard
    expect(VolumeCurve.percent(free.shortcutStepped(0.5, by: 1)) == 55, "a step is 5%")
    expect(VolumeCurve.percent(free.shortcutStepped(0.53, by: -1)) == 50, "steps land on the 5% grid")
    expect(free.shortcutStepped(1, by: 1) == 1 && free.shortcutStepped(0.02, by: -1) == 0, "steps stop at the ends")
    var volume = 1.0
    for _ in 0..<20 {
        volume = free.shortcutStepped(volume, by: -1)
    }
    expect(volume == 0, "twenty steps down reach 0%")
}

// Reset: every app back to 100% on the system output, pins kept.
do {
    let defaults = UserDefaults(suiteName: "reset-check")!
    defaults.removePersistentDomain(forName: "reset-check")
    let store = MixerSettingsStore(defaults: defaults)
    store.setVolume(AppVolume(volume: 0.3, isMuted: true), for: "com.spotify.client", on: "speakers")
    store.setOutputDevice(uid: "headphones", name: "Headphones", for: "com.spotify.client")
    store.setVolume(AppVolume(volume: 0.5, isMuted: false), for: "us.zoom.xos", on: "speakers")
    store.setPinned(true, for: "us.zoom.xos")
    store.resetApps()
    expect(store.appKeys == ["us.zoom.xos"], "only the pinned app is kept")
    expect(store.settings(for: "us.zoom.xos") == AppSettings(isPinned: true), "at 100% on the system output")
    expect(store.volume(for: "com.spotify.client", on: "speakers") == AppVolume(), "the others are forgotten")
    expect(MixerSettingsStore(defaults: defaults).appKeys == ["us.zoom.xos"], "and it is saved")
    defaults.removePersistentDomain(forName: "reset-check")
}

// Target app: the latest to start playing, or the app in front when nothing plays.
do {
    let start = Date(timeIntervalSince1970: 1_000)
    let playing = ["com.spotify.client": start, "us.zoom.xos": start.addingTimeInterval(30)]
    expect(TargetApp.choose(playingSince: playing, frontmost: "com.apple.Safari") == "us.zoom.xos", "the latest wins")
    expect(TargetApp.choose(playingSince: [:], frontmost: "com.apple.Safari") == "com.apple.Safari", "else the front")
    expect(TargetApp.choose(playingSince: [:], frontmost: nil) == nil, "or nothing")
    let tie = ["b": start, "a": start]
    expect(TargetApp.choose(playingSince: tie, frontmost: nil) == "a", "a tie always goes the same way")
    expect(TargetApp.choose(playingSince: tie, frontmost: "b") == "b", "unless the app in front is in it")
    expect(
        TargetApp.choose(playingSince: playing, frontmost: "com.spotify.client") == "us.zoom.xos",
        "the front app only breaks ties"
    )
}

// Ignored apps: never routed, forgotten otherwise, and never pinned at the same time.
do {
    let defaults = UserDefaults(suiteName: "ignore-check")!
    defaults.removePersistentDomain(forName: "ignore-check")
    let store = MixerSettingsStore(defaults: defaults)
    store.setVolume(AppVolume(volume: 0.2, isMuted: true), for: "com.apple.Music", on: "speakers")
    store.setOutputDevice(uid: "headphones", name: "Headphones", for: "com.apple.Music")
    store.setPinned(true, for: "com.apple.Music")
    store.setIgnored(true, for: "com.apple.Music")
    let ignored = store.settings(for: "com.apple.Music")
    expect(store.ignoredApps == ["com.apple.Music"] && store.pinnedApps.isEmpty, "ignoring unpins")
    expect(ignored == AppSettings(isIgnored: true), "and forgets the volume and device")
    expect(!ignored.isDefault, "an ignored app is worth keeping")
    expect(
        !AppSettings(volumes: ["speakers": AppVolume(volume: 0.2)], isIgnored: true)
            .needsRoute(systemOutputUID: "speakers", connectedUIDs: ["speakers"], scale: .standard),
        "an ignored app is never routed"
    )
    expect(MixerSettingsStore(defaults: defaults).ignoredApps == ["com.apple.Music"], "it stays ignored")
    store.resetApps()
    expect(store.ignoredApps == ["com.apple.Music"], "a reset keeps it ignored")
    store.setPinned(true, for: "com.apple.Music")
    expect(store.ignoredApps.isEmpty && store.pinnedApps == ["com.apple.Music"], "pinning brings it back")
    store.setIgnored(true, for: "com.apple.Music")
    store.setIgnored(false, for: "com.apple.Music")
    expect(store.appKeys.isEmpty, "and so does stopping to ignore it, as a new app")
    let old = Data(#"{"volumes":{},"isPinned":true}"#.utf8)
    expect((try? JSONDecoder().decode(AppSettings.self, from: old))?.isIgnored == false, "old saves load not ignored")
    defaults.removePersistentDomain(forName: "ignore-check")
}

print("\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
