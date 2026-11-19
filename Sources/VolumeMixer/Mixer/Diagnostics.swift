import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// `VolumeMixer --list` prints what the mixer sees without starting the app or touching any audio;
/// Copy Diagnostics reports what the running app does, for a bug report.
@MainActor
enum Diagnostics {
    /// Lines of this run's own log the report carries, newest last.
    private static let logLines = 80

    /// Versions, the Mac's model, what the mixer is doing and its recent log. Names apps and
    /// devices, and nothing else about the Mac.
    static func report(mixer: [String]) async -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        var lines = [
            "Volume Mixer \(version) (\(build))",
            "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion) (\(sysctlString("kern.osversion"))), \(sysctlString("hw.model"))",
            "",
        ]
        lines += mixer
        lines += ["", "Recent log:"]
        lines += await recentLog()
        return lines.joined(separator: "\n")
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return "?" }
        return value.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// Read off the main thread: the log store takes seconds to open.
    private static func recentLog() async -> [String] {
        let limit = logLines
        return await Task.detached(priority: .userInitiated) {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", logSubsystem))
                var lines: [String] = []
                for case let entry as OSLogEntryLog in entries {
                    lines.append("\(entry.date.formatted(date: .omitted, time: .standard)) \(entry.composedMessage)")
                    if lines.count > limit {
                        lines.removeFirst()
                    }
                }
                return lines
            } catch {
                return ["(log unavailable: \(error.localizedDescription))"]
            }
        }.value
    }

    static func printAudioClients() {
        let defaultOutput = try? AudioObjectID.system.read(
            kAudioHardwarePropertyDefaultOutputDevice,
            initial: AudioObjectID.unknown
        )
        let device = defaultOutput ?? .unknown
        let name = (try? device.readString(kAudioObjectPropertyName)) ?? "?"
        let uid = (try? device.readString(kAudioDevicePropertyDeviceUID)) ?? "?"
        let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        let outputScope = kAudioObjectPropertyScopeOutput
        let volume = (try? device.read(volumeSelector, scope: outputScope, initial: Float32(-1))) ?? -1
        print("Output device \(device): \(name) [\(uid)]")
        print(
            "  streams in \(device.streamCount(scope: kAudioObjectPropertyScopeInput)), out \(device.streamCount(scope: outputScope))"
        )
        print(
            "  volume \(volume), settable \(device.isSettable(volumeSelector, scope: outputScope)), mute settable \(device.isSettable(kAudioDevicePropertyMute, scope: outputScope))"
        )

        let output = SystemOutput()
        output.start()
        print("Output devices: \(output.devices.count)")
        for item in output.devices {
            let marker = item.id == output.deviceID ? "*" : " "
            print("  \(marker) \(item.id) \(item.name) [\(item.symbolName)] \(item.uid)")
        }

        let resolver = AppResolver()
        let clients = AudioProcessMonitor.snapshot().values.sorted { $0.pid < $1.pid }
        print("Audio clients: \(clients.count)")
        for client in clients {
            let identity = resolver.identity(for: client)
            let state = client.isPlaying ? "PLAYING" : "idle   "
            print(
                "  \(state) pid \(client.pid) object \(client.objectID) bundle \(client.bundleID ?? "-") -> \(identity.name) [\(identity.key)]"
            )
        }
    }
}
