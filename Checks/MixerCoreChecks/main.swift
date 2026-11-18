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
expect(VolumeCurve.position(of: 1) == VolumeCurve.unityPosition, "100% sits on the mark")
expect(VolumeCurve.position(of: 2) == 1, "200% is the end of the slider")
expect(nearlyEqual(Float(VolumeCurve.position(of: 0.5)), 0.375), "50% is half way to the mark")
expect(VolumeCurve.volume(atPosition: VolumeCurve.unityPosition + 0.01) == 1, "a drag next to the mark snaps onto 100%")
expect(nearlyEqual(Float(VolumeCurve.volume(atPosition: 0.875)), 1.5), "half way through the boost quarter is 150%")
for volume in [0.0, 0.2, 0.6, 1.3, 1.8, 2.0] {
    let roundTrip = VolumeCurve.volume(atPosition: VolumeCurve.position(of: volume))
    expect(nearlyEqual(Float(roundTrip), Float(volume)), "position and volume convert both ways for \(volume)")
}
expect(AppVolume(volume: 1.4).isBoosted, "above 100% is boost")
expect(AppVolume(volume: 1.4).needsRouting, "a boosted app is routed")
expect(AppVolume(volume: 0.4).needsRouting, "a quieter app is routed")

// Settings survive a relaunch and drop apps back at full volume.
do {
    let suiteName = "MixerCoreChecks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else { fatalError("no defaults suite") }
    let store = AppVolumeStore(defaults: defaults)
    store["com.spotify.client"] = AppVolume(volume: 0.3)
    store["com.google.Chrome"] = AppVolume(volume: 1, isMuted: true)
    let reloaded = AppVolumeStore(defaults: defaults)
    expect(reloaded["com.spotify.client"] == AppVolume(volume: 0.3), "a volume is restored after relaunch")
    expect(reloaded["com.google.Chrome"].isMuted, "mute is restored after relaunch")
    reloaded["com.spotify.client"] = AppVolume()
    expect(
        !AppVolumeStore(defaults: defaults).adjustedKeys.contains("com.spotify.client"),
        "an app back at full volume is forgotten"
    )
    expect(reloaded["unknown.app"] == AppVolume(), "an unknown app starts at full volume")
    defaults.removePersistentDomain(forName: suiteName)
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

print("\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
