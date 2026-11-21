/// Everything the mixer remembers about one app.
public struct AppSettings: Codable, Equatable {
    /// UID of the output device the app is sent to, or nil to follow the system output.
    public var outputDeviceUID: String?
    /// The chosen device's name, to show while it is not connected.
    public var outputDeviceName: String?
    /// The app's volume on each output device it has been set on, by device UID.
    public var volumes: [String: AppVolume]
    /// The volume set most recently on any device. A device the app has no volume for starts here,
    /// so plugging in new headphones never brings back a full-volume app.
    public var lastVolume: AppVolume?
    /// Keeps the app's row while it is quiet or not running, so it can be set before it plays.
    public var isPinned: Bool
    /// Left alone: never tapped, never listed, playing as macOS plays it.
    public var isIgnored: Bool

    public init(
        outputDeviceUID: String? = nil,
        outputDeviceName: String? = nil,
        volumes: [String: AppVolume] = [:],
        lastVolume: AppVolume? = nil,
        isPinned: Bool = false,
        isIgnored: Bool = false
    ) {
        self.outputDeviceUID = outputDeviceUID
        self.outputDeviceName = outputDeviceName
        self.volumes = volumes
        self.lastVolume = lastVolume
        self.isPinned = isPinned
        self.isIgnored = isIgnored
    }

    /// Every field may be missing: saves from before a field existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputDeviceUID = try container.decodeIfPresent(String.self, forKey: .outputDeviceUID)
        outputDeviceName = try container.decodeIfPresent(String.self, forKey: .outputDeviceName)
        volumes = try container.decodeIfPresent([String: AppVolume].self, forKey: .volumes) ?? [:]
        lastVolume = try container.decodeIfPresent(AppVolume.self, forKey: .lastVolume)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isIgnored = try container.decodeIfPresent(Bool.self, forKey: .isIgnored) ?? false
    }

    public func volume(on deviceUID: String) -> AppVolume {
        volumes[deviceUID] ?? lastVolume ?? AppVolume()
    }

    /// Where the app plays: its chosen device while connected, otherwise the system output, so
    /// unplugged headphones send the app back to the speakers until they return.
    public func outputDeviceUID(systemOutputUID: String, connectedUIDs: Set<String>) -> String {
        guard let outputDeviceUID, connectedUIDs.contains(outputDeviceUID) else { return systemOutputUID }
        return outputDeviceUID
    }

    /// Whether the app has to go through a tap: turned down, muted, or playing on another device
    /// than the system output. An app at 100% on the system output plays untouched, also when the
    /// device it was sent to happens to be the system output right now.
    public func needsRoute(systemOutputUID: String, connectedUIDs: Set<String>, scale: VolumeScale) -> Bool {
        guard !isIgnored else { return false }
        let deviceUID = outputDeviceUID(systemOutputUID: systemOutputUID, connectedUIDs: connectedUIDs)
        var setting = volume(on: deviceUID)
        setting.volume = scale.clamped(setting.volume)
        return setting.needsRouting || deviceUID != systemOutputUID
    }

    /// Nothing differs from an app the mixer has never seen, so there is nothing to keep.
    public var isDefault: Bool {
        !isPinned && !isIgnored && outputDeviceUID == nil && !(lastVolume?.needsRouting ?? false)
            && volumes.values.allSatisfy { !$0.needsRouting }
    }
}
