import CoreAudio
import Foundation
import MixerCore

/// Plays one process's audio at its own volume.
///
/// A muted process tap captures the process. A private aggregate device holds the tap as an input
/// and the real output device as its clock and output, and its IO callback copies the tap into the
/// output at the app's gain. Private taps and aggregates belong to this process, so if the mixer
/// quits or crashes the system removes them and every app plays normally again.
final class ProcessTap {
    /// Private aggregate devices are visible to the process that made them, so the output list
    /// recognises its own by this prefix.
    static let aggregateUIDPrefix = "com.rokoov.volumemixer.route."

    let processObjectID: AudioObjectID
    let deviceUID: String
    private(set) var isRunning = false

    private let renderer: TapRenderer
    private let deviceInputStreams: Int
    private var tapID = AudioObjectID.unknown
    private var tapUID = ""
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

    init(processObjectID: AudioObjectID, outputDevice: AudioObjectID, gain: Float) throws {
        self.processObjectID = processObjectID
        deviceUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)
        deviceInputStreams = outputDevice.streamCount(scope: kAudioObjectPropertyScopeInput)
        renderer = TapRenderer(tapBufferIndex: deviceInputStreams, gain: gain)
        do {
            try createTap()
            try createAggregateDevice()
            try createIOProc()
            ignoreDeviceInputs()
        } catch {
            invalidate()
            throw error
        }
    }

    deinit { invalidate() }

    var gain: Float {
        get { renderer.gain }
        set { renderer.gain = newValue }
    }

    func takePeak() -> Float { renderer.takePeak() }

    func start() throws {
        guard !isRunning, let ioProcID else { return }
        try check(AudioDeviceStart(aggregateID, ioProcID), "Starting the audio route")
        isRunning = true
    }

    func stop() {
        guard isRunning, let ioProcID else { return }
        AudioDeviceStop(aggregateID, ioProcID)
        isRunning = false
    }

    func invalidate() {
        stop()
        if let ioProcID {
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID.isKnown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID.isKnown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
    }

    private func createTap() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.uuid = UUID()
        description.name = "Volume Mixer \(processObjectID)"
        description.isPrivate = true
        // Muted rather than mutedWhenTapped: the route stops while the app is idle, and when it
        // starts playing again it should lose a few milliseconds instead of playing them at full volume.
        description.muteBehavior = .muted
        tapUID = description.uuid.uuidString
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Creating the process tap")
    }

    private func createAggregateDevice() throws {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Volume Mixer \(processObjectID)",
            kAudioAggregateDeviceUIDKey: "\(Self.aggregateUIDPrefix)\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: deviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: deviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
        ]
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "Creating the aggregate device")
    }

    private func createIOProc() throws {
        let renderer = renderer
        // No dispatch queue: the block runs directly on the real-time IO thread.
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
            renderer.render(input: input, output: output)
        }
        try check(status, "Creating the IO callback")
    }

    /// Marks the output device's own input streams (a headset microphone) unused, so starting the
    /// route never opens the microphone or switches Bluetooth headphones to call quality.
    private func ignoreDeviceInputs() {
        guard deviceInputStreams > 0, let ioProcID else { return }
        let streamCount = deviceInputStreams + 1
        let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) ?? 12
        let size = flagsOffset + streamCount * MemoryLayout<UInt32>.size
        let storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { storage.deallocate() }

        let usage = storage.bindMemory(to: AudioHardwareIOProcStreamUsage.self, capacity: 1)
        usage.pointee.mIOProc = unsafeBitCast(ioProcID, to: UnsafeMutableRawPointer.self)
        usage.pointee.mNumberStreams = UInt32(streamCount)
        let flags = (storage + flagsOffset).bindMemory(to: UInt32.self, capacity: streamCount)
        for index in 0..<streamCount {
            flags[index] = index < deviceInputStreams ? 0 : 1
        }

        var address = AudioObjectPropertyAddress(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        let status = AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(size), storage)
        if status != noErr {
            log.error("Could not mark device inputs unused: \(fourCharacterCode(UInt32(bitPattern: status)), privacy: .public)")
        }
    }
}
