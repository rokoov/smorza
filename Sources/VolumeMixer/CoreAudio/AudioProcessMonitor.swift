import CoreAudio
import Foundation

/// A process connected to the audio system.
struct AudioClient: Equatable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    var isPlaying: Bool
}

/// Keeps the list of audio clients and whether each one is playing sound right now.
@MainActor
final class AudioProcessMonitor {
    private(set) var clients: [AudioObjectID: AudioClient] = [:]
    var onChange: (() -> Void)?

    private var listListener: PropertyListener?
    private var playingListeners: [AudioObjectID: PropertyListener] = [:]

    func start() {
        listListener = PropertyListener(.system, kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.reload()
        }
        reload()
    }

    /// Every client except this app, read straight from the HAL.
    static func snapshot(reusing known: [AudioObjectID: AudioClient] = [:]) -> [AudioObjectID: AudioClient] {
        let ownPID = getpid()
        let objectIDs = (try? AudioObjectID.system.readObjectIDs(kAudioHardwarePropertyProcessObjectList)) ?? []
        var clients: [AudioObjectID: AudioClient] = [:]
        for objectID in objectIDs {
            guard let pid = try? objectID.read(kAudioProcessPropertyPID, initial: pid_t(0)), pid > 0, pid != ownPID else { continue }
            let bundleID: String?
            if let existing = known[objectID], existing.pid == pid {
                bundleID = existing.bundleID
            } else {
                bundleID = (try? objectID.readString(kAudioProcessPropertyBundleID)).flatMap { $0.isEmpty ? nil : $0 }
            }
            clients[objectID] = AudioClient(
                objectID: objectID,
                pid: pid,
                bundleID: bundleID,
                isPlaying: objectID.readBool(kAudioProcessPropertyIsRunningOutput)
            )
        }
        return clients
    }

    private func reload() {
        let next = Self.snapshot(reusing: clients)
        for objectID in next.keys where playingListeners[objectID] == nil {
            playingListeners[objectID] = PropertyListener(objectID, kAudioProcessPropertyIsRunningOutput) { [weak self] in
                self?.updatePlaying(objectID)
            }
        }
        let gone = playingListeners.keys.filter { next[$0] == nil }
        for objectID in gone {
            playingListeners.removeValue(forKey: objectID)?.invalidate()
        }
        clients = next
        onChange?()
    }

    private func updatePlaying(_ objectID: AudioObjectID) {
        guard var client = clients[objectID] else { return }
        let isPlaying = objectID.readBool(kAudioProcessPropertyIsRunningOutput)
        guard isPlaying != client.isPlaying else { return }
        client.isPlaying = isPlaying
        clients[objectID] = client
        onChange?()
    }
}
