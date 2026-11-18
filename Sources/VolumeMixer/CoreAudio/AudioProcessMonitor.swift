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
    private var playingListeners: [AudioObjectID: [PropertyListener]] = [:]

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
            // macOS announces IsRunning but changes IsRunningOutput without a notification
            // (checked on macOS 26.3), so either one triggers a fresh read of every client.
            playingListeners[objectID] = [kAudioProcessPropertyIsRunning, kAudioProcessPropertyIsRunningOutput].map { selector in
                PropertyListener(objectID, selector) { [weak self] in
                    self?.refreshPlaying()
                }
            }
        }
        let gone = playingListeners.keys.filter { next[$0] == nil }
        for objectID in gone {
            playingListeners.removeValue(forKey: objectID)?.forEach { $0.invalidate() }
        }
        clients = next
        onChange?()
    }

    /// Re-reads whether each client is playing. Also called on a timer, since a process that is
    /// already doing input can start output without any notification at all.
    func refreshPlaying() {
        var changed = false
        for (objectID, client) in clients {
            let isPlaying = objectID.readBool(kAudioProcessPropertyIsRunningOutput)
            guard isPlaying != client.isPlaying else { continue }
            clients[objectID]?.isPlaying = isPlaying
            changed = true
        }
        if changed { onChange?() }
    }
}
