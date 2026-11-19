import CoreAudio
import Foundation

/// The aggregate devices the mixer plays through: a real output device as clock and output, plus
/// one process tap as an input. Private means only this process sees them, and macOS removes them
/// when it exits.
enum PrivateAggregateDevice {
    /// Every UID starts with this, so the output list can leave the mixer's own devices out.
    static let uidPrefix = "com.rokoov.volumemixer.route."

    static func make(name: String, outputDeviceUID: String, tapUUID: UUID) throws -> AudioObjectID {
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uidPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID.uuidString, kAudioSubTapDriftCompensationKey: true]
            ],
        ]
        var deviceID = AudioObjectID.unknown
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &deviceID), "Creating \(name)")
        return deviceID
    }

    /// Where the tap's stream sits among the aggregate device's input streams: last, after any inputs
    /// of the output device (a headset microphone). Counted on the aggregate itself, because an output
    /// device that is an aggregate does not pass all of its inputs on.
    static func tapStreamIndex(of aggregateID: AudioObjectID) throws -> Int {
        let taps = (try? aggregateID.readObjectIDs(kAudioAggregateDevicePropertySubTapList)) ?? []
        let inputs = aggregateID.streamCount(scope: kAudioObjectPropertyScopeInput)
        guard !taps.isEmpty, inputs > 0 else {
            throw CoreAudioError(operation: "Finding the tap's stream", status: kAudioHardwareUnspecifiedError)
        }
        return inputs - 1
    }

    /// Marks the output device's own input streams (a headset microphone) unused for one IO
    /// callback. They come before the tap's stream, and leaving them on would open the microphone
    /// or drop Bluetooth headphones to call quality.
    static func ignoreInputStreams(_ count: Int, of deviceID: AudioObjectID, procID: AudioDeviceIOProcID) {
        guard count > 0 else { return }
        let streamCount = count + 1
        let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) ?? 12
        let size = flagsOffset + streamCount * MemoryLayout<UInt32>.size
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: size,
            alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment
        )
        defer { storage.deallocate() }

        let usage = storage.bindMemory(to: AudioHardwareIOProcStreamUsage.self, capacity: 1)
        usage.pointee.mIOProc = unsafeBitCast(procID, to: UnsafeMutableRawPointer.self)
        usage.pointee.mNumberStreams = UInt32(streamCount)
        let flags = (storage + flagsOffset).bindMemory(to: UInt32.self, capacity: streamCount)
        for index in 0..<streamCount {
            flags[index] = index < count ? 0 : 1
        }

        var address = AudioObjectPropertyAddress(
            kAudioDevicePropertyIOProcStreamUsage,
            scope: kAudioObjectPropertyScopeInput
        )
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(size), storage)
        if status != noErr {
            let code = fourCharacterCode(UInt32(bitPattern: status))
            log.error("Could not mark device inputs unused: \(code, privacy: .public)")
        }
    }
}
