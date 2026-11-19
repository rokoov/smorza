import CoreAudio
import Foundation

/// Copies one tapped stereo stream into a device's output buffers at a given gain, through a peak
/// limiter so a boosted app never clips.
///
/// `render` runs on the HAL's real-time IO thread, so it never allocates, locks or calls into
/// Objective-C. The target gain and the peak meter are single aligned 32-bit floats shared with
/// the main thread: a torn value cannot happen on arm64 or x86_64, and a stale one lasts one buffer.
public final class TapRenderer {
    /// Loudest sample the limiter lets through, just under full scale (-0.18 dBFS).
    public static let ceiling: Float = 0.98
    /// Seconds the limiter takes to recover most of its gain after a peak. Shorter pumps audibly;
    /// longer holds quiet passages down after a loud one.
    public static let releaseTime = 0.08
    /// Gain gap the release closes in one step, 0.009 dB: inaudible. A release step near 1 stalls
    /// once gap × step drops under half a Float ulp, which happens below about 0.0009 at 192 kHz.
    private static let releaseSnap: Float = 0.001

    /// Index of the tap's stream among the aggregate device's input buffers. The output device's
    /// own input streams (a headset microphone) come first, then the tap.
    public let tapBufferIndex: Int

    private let targetGain: UnsafeMutablePointer<Float>
    private let peakLevel: UnsafeMutablePointer<Float>
    private let releaseStep: Float
    private var currentGain: Float
    private var limiterGain: Float = 1

    public init(tapBufferIndex: Int, gain: Float, sampleRate: Double = 48_000) {
        self.tapBufferIndex = tapBufferIndex
        targetGain = .allocate(capacity: 1)
        targetGain.initialize(to: max(0, gain))
        peakLevel = .allocate(capacity: 1)
        peakLevel.initialize(to: 0)
        currentGain = max(0, gain)
        releaseStep = Float(1 - exp(-1 / (max(sampleRate, 1) * Self.releaseTime)))
    }

    deinit {
        targetGain.deallocate()
        peakLevel.deallocate()
    }

    public var gain: Float {
        get { targetGain.pointee }
        set { targetGain.pointee = max(0, newValue) }
    }

    /// The loudest input sample since the previous call.
    public func takePeak() -> Float {
        let peak = peakLevel.pointee
        peakLevel.pointee = 0
        return peak
    }

    public func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        // Ramp across the buffer so a moving slider never clicks.
        let startGain = currentGain
        let endGain = targetGain.pointee
        currentGain = endGain

        var source: UnsafeMutablePointer<Float>?
        var sourceChannels = 0
        var sourceFrames = 0
        if !inputs.isEmpty {
            let tap = inputs[min(tapBufferIndex, inputs.count - 1)]
            if tap.mNumberChannels > 0, let data = tap.mData {
                source = data.assumingMemoryBound(to: Float.self)
                sourceChannels = Int(tap.mNumberChannels)
                sourceFrames = Int(tap.mDataByteSize) / (MemoryLayout<Float>.size * sourceChannels)
            }
        }
        trackPeak(source, sampleCount: sourceFrames * sourceChannels)

        var totalChannels = 0
        var frames = 0
        for buffer in outputs {
            let channels = Int(buffer.mNumberChannels)
            totalChannels += channels
            if channels > 0 {
                frames = max(frames, Self.frameCount(of: buffer))
            }
        }
        let step = frames > 0 ? (endGain - startGain) / Float(frames) : 0

        for frame in 0..<frames {
            let gain = startGain + step * Float(frame + 1)
            var left: Float = 0
            var right: Float = 0
            if let source, frame < sourceFrames {
                left = source[frame * sourceChannels] * gain
                right =
                    (sourceChannels > 1 ? source[frame * sourceChannels + 1] : source[frame * sourceChannels]) * gain
            }
            let reduction = limit(peak: max(abs(left), abs(right)))
            left *= reduction
            right *= reduction

            var firstChannel = 0
            for buffer in outputs {
                let channels = Int(buffer.mNumberChannels)
                defer { firstChannel += channels }
                guard channels > 0, let data = buffer.mData, frame < Self.frameCount(of: buffer) else { continue }
                let destination = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<channels {
                    destination[frame * channels + channel] = Self.sample(
                        forChannel: firstChannel + channel,
                        of: totalChannels,
                        left: left,
                        right: right
                    )
                }
            }
        }
    }

    /// The gain reduction for one frame: drops at once far enough to keep the peak under the
    /// ceiling, then recovers over the release time.
    @inline(__always)
    private func limit(peak: Float) -> Float {
        let needed = peak > Self.ceiling ? Self.ceiling / peak : 1
        if needed < limiterGain {
            limiterGain = needed
        } else {
            limiterGain += (needed - limiterGain) * releaseStep
            // Near 1 the steps fall below Float precision and the last gap never closes on its own.
            if needed - limiterGain < Self.releaseSnap {
                limiterGain = needed
            }
        }
        return limiterGain
    }

    @inline(__always)
    private static func frameCount(of buffer: AudioBuffer) -> Int {
        let channels = Int(buffer.mNumberChannels)
        return channels > 0 ? Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels) : 0
    }

    @inline(__always)
    private static func sample(forChannel channel: Int, of totalChannels: Int, left: Float, right: Float) -> Float {
        if totalChannels == 1 { return (left + right) * 0.5 }
        if channel == 0 { return left }
        if channel == 1 { return right }
        return 0
    }

    private func trackPeak(_ samples: UnsafeMutablePointer<Float>?, sampleCount: Int) {
        guard let samples, sampleCount > 0 else { return }
        var peak = peakLevel.pointee
        for index in 0..<sampleCount {
            peak = max(peak, abs(samples[index]))
        }
        peakLevel.pointee = peak
    }
}
