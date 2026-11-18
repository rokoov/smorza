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
        storage.forEach { $0.deallocate() }
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

    [input, mono, split, surround].forEach { $0.release() }
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

// Volume curve.
expect(VolumeCurve.gain(sliderValue: 1, isMuted: false) == 1, "full slider is unity gain")
expect(VolumeCurve.gain(sliderValue: 0.999, isMuted: false) == 1, "the top of the slider snaps to unity gain")
expect(
    nearlyEqual(VolumeCurve.gain(sliderValue: 0.5, isMuted: false), 0.25),
    "half slider is a quarter of the amplitude"
)
expect(VolumeCurve.gain(sliderValue: 0.8, isMuted: true) == 0, "muted is silent")
expect(VolumeCurve.gain(sliderValue: -1, isMuted: false) == 0, "slider clamps below zero")
expect(VolumeCurve.percent(0.996) == 100, "percent rounds to the label the user sees")
expect(!AppVolume().needsRouting, "a default app plays untouched")
expect(AppVolume(volume: 1, isMuted: true).needsRouting, "a muted app is routed")
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

print("\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
