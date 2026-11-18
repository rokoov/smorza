import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import SwiftUI

/// `VolumeMixer --list`: what the mixer sees, without starting the app or touching any audio.
/// `VolumeMixer --snapshot <dir>`: the panel rendered with live data in light and dark, routing off.
/// `VolumeMixer --snapshot-demo <dir>`: the same with sample apps and devices, for the README.
@MainActor
enum Diagnostics {
    static func writeSnapshots(to directory: String, demo: Bool) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let model = MixerModel()
        model.routesAudio = false
        if demo {
            loadDemo(into: model)
        } else {
            model.start()
        }

        let corners = RoundedRectangle(cornerRadius: 14, style: .continuous)
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            guard let appearance = NSAppearance(named: appearanceName) else { continue }
            let panel = MixerPanel(model: model)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(corners)
                .overlay(corners.strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
                .padding(28)
            let host = NSHostingView(rootView: panel)
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

    private static func loadDemo(into model: MixerModel) {
        func icon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }
        model.showDemo([
            MixerEntry(
                id: "com.google.Chrome",
                name: "Google Chrome",
                icon: icon("/Applications/Google Chrome.app"),
                volume: 1,
                isMuted: false,
                isPlaying: true
            ),
            MixerEntry(
                id: "com.spotify.client",
                name: "Spotify",
                icon: icon("/Applications/Spotify.app"),
                volume: 0.6,
                isMuted: false,
                isPlaying: true
            ),
            MixerEntry(
                id: "com.hnc.Discord",
                name: "Discord",
                icon: icon("/Applications/Discord.app"),
                volume: 0.35,
                isMuted: false,
                isPlaying: false
            ),
            MixerEntry(
                id: "com.apple.Music",
                name: "Music",
                icon: icon("/System/Applications/Music.app"),
                volume: 0.8,
                isMuted: true,
                isPlaying: false
            ),
        ])
        model.output.showDemo(
            name: "MacBook Pro Speakers",
            symbolName: "laptopcomputer",
            volume: 0.5,
            devices: [
                OutputDevice(id: 9001, name: "MacBook Pro Speakers", symbolName: "laptopcomputer", isBuiltIn: true),
                OutputDevice(id: 9002, name: "AirPods Pro", symbolName: "airpodspro", isBuiltIn: false),
                OutputDevice(id: 9003, name: "Studio Display", symbolName: "display", isBuiltIn: false),
            ]
        )
    }

    static func printAudioClients() {
        let device =
            (try? AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID.unknown))
            ?? .unknown
        let name = (try? device.readString(kAudioObjectPropertyName)) ?? "?"
        let uid = (try? device.readString(kAudioDevicePropertyDeviceUID)) ?? "?"
        let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        let volume =
            (try? device.read(volumeSelector, scope: kAudioObjectPropertyScopeOutput, initial: Float32(-1))) ?? -1
        print("Output device \(device): \(name) [\(uid)]")
        print(
            "  streams in \(device.streamCount(scope: kAudioObjectPropertyScopeInput)), out \(device.streamCount(scope: kAudioObjectPropertyScopeOutput))"
        )
        print(
            "  volume \(volume), settable \(device.isSettable(volumeSelector, scope: kAudioObjectPropertyScopeOutput)), mute settable \(device.isSettable(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput))"
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
