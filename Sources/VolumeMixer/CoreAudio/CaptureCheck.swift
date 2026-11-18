import CoreAudio
import Foundation

/// Proves macOS lets this app hear other apps before any app is muted for a route.
///
/// The mixer plays an inaudible constant signal on the output device and reads it back through an
/// unmuted tap of its own process. Real samples mean System Audio Recording is allowed. A denied
/// tap delivers zeros without an error from any call, and the TCC check reports "undetermined"
/// even once allowed, so hearing the signal is the only reliable answer. Starting a check is also
/// what makes macOS ask the first time.
final class CaptureCheck {
    /// -100 dBFS and constant: nothing to hear, and nothing a resampler would filter away.
    private static let signalLevel: Float = 0.00001

    private let outputDevice: AudioObjectID
    private let heard = SignalFlag()
    private var signalProcID: AudioDeviceIOProcID?
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var listenProcID: AudioDeviceIOProcID?

    init(outputDevice: AudioObjectID) throws {
        self.outputDevice = outputDevice
        do {
            try startSignal()
            try startListening()
        } catch {
            invalidate()
            throw error
        }
    }

    deinit { invalidate() }

    var hasHeardSignal: Bool { heard.isRaised }

    func invalidate() {
        if let listenProcID {
            AudioDeviceStop(aggregateID, listenProcID)
            AudioDeviceDestroyIOProcID(aggregateID, listenProcID)
            self.listenProcID = nil
        }
        if aggregateID.isKnown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID.isKnown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
        if let signalProcID {
            AudioDeviceStop(outputDevice, signalProcID)
            AudioDeviceDestroyIOProcID(outputDevice, signalProcID)
            self.signalProcID = nil
        }
    }

    /// Forgets the HAL objects without touching them, for after a coreaudiod restart.
    func abandon() {
        signalProcID = nil
        listenProcID = nil
        aggregateID = .unknown
        tapID = .unknown
    }

    private func startSignal() throws {
        let level = Self.signalLevel
        let status = AudioDeviceCreateIOProcIDWithBlock(&signalProcID, outputDevice, nil) { _, _, _, output, _ in
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) {
                    samples[index] = level
                }
            }
        }
        try check(status, "Creating the check signal")
        try check(AudioDeviceStart(outputDevice, signalProcID), "Starting the check signal")
    }

    private func startListening() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: [try Self.ownProcessObject()])
        description.uuid = UUID()
        description.name = "Volume Mixer capture check"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Creating the check tap")

        let deviceUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)
        let deviceInputStreams = outputDevice.streamCount(scope: kAudioObjectPropertyScopeInput)
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Volume Mixer capture check",
            kAudioAggregateDeviceUIDKey: "\(ProcessTap.aggregateUIDPrefix)check.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregateID), "Creating the check device")

        let heard = heard
        let status = AudioDeviceCreateIOProcIDWithBlock(&listenProcID, aggregateID, nil) { _, input, _, output, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            if !inputs.isEmpty {
                let tap = inputs[min(deviceInputStreams, inputs.count - 1)]
                if let data = tap.mData {
                    let samples = data.assumingMemoryBound(to: Float.self)
                    for index in 0..<(Int(tap.mDataByteSize) / MemoryLayout<Float>.size) where samples[index] != 0 {
                        heard.raise()
                        break
                    }
                }
            }
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
        }
        try check(status, "Creating the check callback")
        if let listenProcID {
            ignoreInputStreams(deviceInputStreams, of: aggregateID, procID: listenProcID)
        }
        try check(AudioDeviceStart(aggregateID, listenProcID), "Starting the check")
    }

    private static func ownProcessObject() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var objectID = AudioObjectID.unknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(.system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &objectID)
        try check(status, "Finding this app's audio process")
        guard objectID.isKnown else {
            throw CoreAudioError(operation: "Finding this app's audio process", status: kAudioHardwareBadObjectError)
        }
        return objectID
    }
}
