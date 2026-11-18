import AudioToolbox
import CoreAudio
import Foundation

/// `VolumeMixer --list`: what the mixer sees, without starting the app or touching any audio.
@MainActor
enum Diagnostics {
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
            print("  \(item.id == output.deviceID ? "*" : " ") \(item.id) \(item.name) [\(item.symbolName)]")
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
