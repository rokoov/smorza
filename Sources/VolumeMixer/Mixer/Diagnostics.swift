import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import SwiftUI

/// `VolumeMixer --list`: what the mixer sees, without starting the app or touching any audio.
/// `VolumeMixer --snapshot <dir>`: the panel rendered with live data in light and dark, routing off.
@MainActor
enum Diagnostics {
    static func writeSnapshots(to directory: String) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let model = MixerModel()
        model.routesAudio = false
        model.start()

        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            let host = NSHostingView(rootView: MixerPanel(model: model).background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = appearance
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = appearance
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            window.setContentSize(host.frame.size)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("panel-\(name).png")
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                print("Wrote \(url.path)")
            }
        }
    }

    static func printAudioClients() {
        let device = (try? AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID.unknown)) ?? .unknown
        let name = (try? device.readString(kAudioObjectPropertyName)) ?? "?"
        let uid = (try? device.readString(kAudioDevicePropertyDeviceUID)) ?? "?"
        let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        let volume = (try? device.read(volumeSelector, scope: kAudioObjectPropertyScopeOutput, initial: Float32(-1))) ?? -1
        print("Output device \(device): \(name) [\(uid)]")
        print("  streams in \(device.streamCount(scope: kAudioObjectPropertyScopeInput)), out \(device.streamCount(scope: kAudioObjectPropertyScopeOutput))")
        print("  volume \(volume), settable \(device.isSettable(volumeSelector, scope: kAudioObjectPropertyScopeOutput)), mute settable \(device.isSettable(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput))")

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
            print("  \(state) pid \(client.pid) object \(client.objectID) bundle \(client.bundleID ?? "-") -> \(identity.name) [\(identity.key)]")
        }
    }
}
