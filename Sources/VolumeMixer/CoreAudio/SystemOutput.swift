import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// The default output device: its name, its own volume and mute, and when it changes.
@MainActor
@Observable
final class SystemOutput {
    private(set) var deviceID = AudioObjectID.unknown
    private(set) var name = ""
    private(set) var volume: Double = 0
    private(set) var isMuted = false
    private(set) var canSetVolume = false
    private(set) var canMute = false
    private(set) var symbolName = "hifispeaker.fill"

    @ObservationIgnored var onDeviceChange: (() -> Void)?
    @ObservationIgnored private var defaultDeviceListener: PropertyListener?
    @ObservationIgnored private var levelListeners: [PropertyListener] = []

    private static let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    private static let outputScope = kAudioObjectPropertyScopeOutput

    func start() {
        defaultDeviceListener = PropertyListener(.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.reloadDevice()
        }
        reloadDevice()
    }

    func setVolume(_ value: Double) {
        guard canSetVolume else { return }
        let clamped = Float32(min(max(value, 0), 1))
        try? deviceID.write(Self.volumeSelector, scope: Self.outputScope, value: clamped)
        volume = Double(clamped)
        if isMuted, clamped > 0 { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        guard canMute else { return }
        try? deviceID.write(kAudioDevicePropertyMute, scope: Self.outputScope, value: UInt32(muted ? 1 : 0))
        isMuted = muted
    }

    func refreshLevels() {
        volume = Double((try? deviceID.read(Self.volumeSelector, scope: Self.outputScope, initial: Float32(0))) ?? 0)
        isMuted = deviceID.readBool(kAudioDevicePropertyMute, scope: Self.outputScope)
    }

    private func reloadDevice() {
        let current = (try? AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID.unknown)) ?? .unknown
        let changed = current != deviceID
        deviceID = current
        name = (try? current.readString(kAudioObjectPropertyName)) ?? "No output device"
        canSetVolume = current.isSettable(Self.volumeSelector, scope: Self.outputScope)
        canMute = current.isSettable(kAudioDevicePropertyMute, scope: Self.outputScope)
        symbolName = Self.symbolName(forTransport: (try? current.read(kAudioDevicePropertyTransportType, initial: UInt32(0))) ?? 0)
        levelListeners = [Self.volumeSelector, kAudioDevicePropertyMute].map { selector in
            PropertyListener(current, selector, scope: Self.outputScope) { [weak self] in
                self?.refreshLevels()
            }
        }
        refreshLevels()
        if changed { onDeviceChange?() }
    }

    private static func symbolName(forTransport transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeUSB: return "cable.connector"
        default: return "hifispeaker.fill"
        }
    }
}
