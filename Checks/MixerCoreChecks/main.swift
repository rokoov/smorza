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

// Row order: playing apps first, then by name; open panels keep rows in place.
struct Row: MixerRowItem {
    let id: String
    let isPlaying: Bool
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
    expect(store.volume(for: "spotify", on: "x").volume == 0.4, "a version 2 save loads into version 3")
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

print("\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
