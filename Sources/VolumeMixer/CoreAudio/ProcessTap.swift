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
    /// Inputs of the output device (a headset microphone) that come ahead of the tap's stream.
    private let inputsAheadOfTap: Int
    private let tapUUID: UUID
    private var tapID = AudioObjectID.unknown
    private var aggregateID = AudioObjectID.unknown
    private var ioProcID: AudioDeviceIOProcID?

    init(label: String, processObjectIDs: [AudioObjectID], outputDevice: AudioObjectID, gain: Float) throws {
        self.label = label
        self.processObjectIDs = processObjectIDs
        self.outputDevice = outputDevice
        deviceUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)
        let tapUUID = UUID()
        let parts = try Self.makeTapAndAggregate(of: processObjectIDs, tapUUID: tapUUID, outputDeviceUID: deviceUID)
        self.tapUUID = tapUUID
        tapID = parts.tapID
        aggregateID = parts.aggregateID
        inputsAheadOfTap = parts.tapStreamIndex
        // The limiter's release is timed in samples at the rate the route will run at.
        let sampleRate =
            (try? outputDevice.read(kAudioDevicePropertyNominalSampleRate, initial: Float64(48_000))) ?? 48_000
        renderer = TapRenderer(tapBufferIndex: parts.tapStreamIndex, gain: gain, sampleRate: sampleRate)
        do {
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
        var description = Self.makeDescription(objectIDs, tapUUID: tapUUID)
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

    /// Creates the muted tap and the aggregate device that plays it, and finds the tap's stream among
    /// the aggregate's inputs. Leaves nothing behind when it throws.
    private static func makeTapAndAggregate(
        of processObjectIDs: [AudioObjectID],
        tapUUID: UUID,
        outputDeviceUID: String
    ) throws -> (tapID: AudioObjectID, aggregateID: AudioObjectID, tapStreamIndex: Int) {
        var tapID = AudioObjectID.unknown
        var aggregateID = AudioObjectID.unknown
        do {
            let description = makeDescription(processObjectIDs, tapUUID: tapUUID)
            try check(AudioHardwareCreateProcessTap(description, &tapID), "Creating the tap")
            aggregateID = try PrivateAggregateDevice.make(
                name: "Volume Mixer route",
                outputDeviceUID: outputDeviceUID,
                tapUUID: tapUUID
            )
            return (tapID, aggregateID, try PrivateAggregateDevice.tapStreamIndex(of: aggregateID))
        } catch {
            if aggregateID.isKnown {
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID.isKnown {
                AudioHardwareDestroyProcessTap(tapID)
            }
            throw error
        }
    }

    private static func makeDescription(_ objectIDs: [AudioObjectID], tapUUID: UUID) -> CATapDescription {
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
            PrivateAggregateDevice.ignoreInputStreams(inputsAheadOfTap, of: aggregateID, procID: ioProcID)
        }
    }
}
