import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// A device sound can be sent to, as the output list shows it.
struct OutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let symbolName: String
    let isBuiltIn: Bool
}

/// The default output device: its name, its own volume and mute, the devices it can switch to,
/// and when it changes.
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
    private(set) var devices: [OutputDevice] = []

    @ObservationIgnored var onDeviceChange: (() -> Void)?
    @ObservationIgnored private var defaultDeviceListener: PropertyListener?
    @ObservationIgnored private var deviceListListener: PropertyListener?
    @ObservationIgnored private var levelListeners: [PropertyListener] = []

    private static let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    private static let outputScope = kAudioObjectPropertyScopeOutput

    func start() {
        defaultDeviceListener = PropertyListener(.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.reloadDevice()
        }
        deviceListListener = PropertyListener(.system, kAudioHardwarePropertyDevices) { [weak self] in
            self?.reloadDeviceList()
        }
        reloadDeviceList()
        reloadDevice()
    }

    func select(_ device: OutputDevice) {
        guard device.id != deviceID else { return }
        do {
            try AudioObjectID.system.write(kAudioHardwarePropertyDefaultOutputDevice, value: device.id)
            log.notice("Output switched to \(device.name, privacy: .public)")
        } catch {
            log.error("Could not switch output to \(device.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
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
        symbolName = Self.symbolName(for: current, name: name)
        levelListeners = [Self.volumeSelector, kAudioDevicePropertyMute].map { selector in
            PropertyListener(current, selector, scope: Self.outputScope) { [weak self] in
                self?.refreshLevels()
            }
        }
        refreshLevels()
        if changed { onDeviceChange?() }
    }

    private func reloadDeviceList() {
        let deviceIDs = (try? AudioObjectID.system.readObjectIDs(kAudioHardwarePropertyDevices)) ?? []
        let found = deviceIDs.compactMap(Self.outputDevice)
        let sorted = found.sorted { first, second in
            if first.isBuiltIn != second.isBuiltIn { return first.isBuiltIn }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
        if sorted != devices {
            devices = sorted
        }
    }

    /// The devices macOS itself would offer as an output: no hidden ones, none that cannot be the
    /// default, and none of this app's own route devices.
    private static func outputDevice(_ deviceID: AudioObjectID) -> OutputDevice? {
        guard deviceID.streamCount(scope: outputScope) > 0,
              deviceID.readBool(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: outputScope),
              !deviceID.readBool(kAudioDevicePropertyIsHidden),
              let uid = try? deviceID.readString(kAudioDevicePropertyDeviceUID),
              !uid.hasPrefix(ProcessTap.aggregateUIDPrefix) else { return nil }
        let name = (try? deviceID.readString(kAudioObjectPropertyName)) ?? uid
        let transport = (try? deviceID.read(kAudioDevicePropertyTransportType, initial: UInt32(0))) ?? 0
        return OutputDevice(
            id: deviceID,
            name: name,
            symbolName: symbolName(for: deviceID, name: name),
            isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn
        )
    }

    private static func symbolName(for deviceID: AudioObjectID, name: String) -> String {
        let transport = (try? deviceID.read(kAudioDevicePropertyTransportType, initial: UInt32(0))) ?? 0
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if name.localizedCaseInsensitiveContains("AirPods Max") { return available("airpodsmax") }
            if name.localizedCaseInsensitiveContains("AirPods Pro") { return available("airpodspro") }
            if name.localizedCaseInsensitiveContains("AirPods") { return available("airpods") }
            return "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeThunderbolt:
            return "display"
        case kAudioDeviceTransportTypeUSB:
            return "cable.connector"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        default:
            return "hifispeaker.fill"
        }
    }

    private static func available(_ symbol: String) -> String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "headphones" : symbol
    }
}
