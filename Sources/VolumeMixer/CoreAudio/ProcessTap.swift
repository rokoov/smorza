import CoreAudio
import Foundation
import MixerCore

/// Plays one app's audio at its own volume on one output device.
///
/// A muted process tap captures every process of the app. A private aggregate device holds the tap
/// as an input and the output device as its clock and output, and its IO callback copies the tap
/// into the output at the app's gain. Private taps and aggregates belong to this process, so if the
/// mixer quits or crashes the system removes them and every app plays normally again.
final class ProcessTap {
    /// The app's name, for the log; the app may be gone by the time the route is.
    let label: String
    let outputDevice: AudioObjectID
    let deviceUID: String
    private(set) var processObjectIDs: [AudioObjectID]
    private(set) var isRunning = false

    private let renderer: TapRenderer
    private let deviceInputStreams: Int
    private let tapUUID = UUID()
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

    init(label: String, processObjectIDs: [AudioObjectID], outputDevice: AudioObjectID, gain: Float) throws {
        self.label = label
        self.processObjectIDs = processObjectIDs
        self.outputDevice = outputDevice
        deviceUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)
        // An output device with its own inputs (a headset) puts them ahead of the tap's stream.
        deviceInputStreams = outputDevice.streamCount(scope: kAudioObjectPropertyScopeInput)
        // The limiter's release is timed in samples at the rate the route will run at.
        let sampleRate =
            (try? outputDevice.read(kAudioDevicePropertyNominalSampleRate, initial: Float64(48_000))) ?? 48_000
        renderer = TapRenderer(tapBufferIndex: deviceInputStreams, gain: gain, sampleRate: sampleRate)
        do {
            try check(AudioHardwareCreateProcessTap(makeDescription(processObjectIDs), &tapID), "Creating the tap")
            aggregateID = try PrivateAggregateDevice.make(
                name: "Volume Mixer route",
                outputDeviceUID: deviceUID,
                tapUUID: tapUUID
            )
            try createIOProc()
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

    /// Changes which processes the tap hears without stopping the route, for an app that starts or
    /// loses a helper process.
    func setProcesses(_ objectIDs: [AudioObjectID]) throws {
        var description = makeDescription(objectIDs)
        var address = AudioObjectPropertyAddress(kAudioTapPropertyDescription)
        let size = UInt32(MemoryLayout<CATapDescription>.size)
        let status = withUnsafeMutablePointer(to: &description) { pointer in
            AudioObjectSetPropertyData(tapID, &address, 0, nil, size, pointer)
        }
        try check(status, "Updating the tapped processes")
        processObjectIDs = objectIDs
    }

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

    /// Forgets the HAL objects without touching them. After coreaudiod restarts they are gone and
    /// their IDs may already belong to something else.
    func abandon() {
        ioProcID = nil
        aggregateID = .unknown
        tapID = .unknown
        isRunning = false
    }

    private func makeDescription(_ objectIDs: [AudioObjectID]) -> CATapDescription {
        let description = CATapDescription(stereoMixdownOfProcesses: objectIDs)
        description.uuid = tapUUID
        description.name = "Volume Mixer route"
        description.isPrivate = true
        // Muted rather than mutedWhenTapped: the route stops while the app is idle, and when it
        // starts playing again it should lose a few milliseconds instead of playing them at full volume.
        description.muteBehavior = .muted
        return description
    }

    private func createIOProc() throws {
        let renderer = renderer
        // No dispatch queue: the block runs directly on the real-time IO thread.
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
            renderer.render(input: input, output: output)
        }
        try check(status, "Creating the IO callback")
        if let ioProcID {
            PrivateAggregateDevice.ignoreInputStreams(deviceInputStreams, of: aggregateID, procID: ioProcID)
        }
    }
}
