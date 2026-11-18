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

    public init(
        outputDeviceUID: String? = nil,
        outputDeviceName: String? = nil,
        volumes: [String: AppVolume] = [:],
        lastVolume: AppVolume? = nil
    ) {
        self.outputDeviceUID = outputDeviceUID
        self.outputDeviceName = outputDeviceName
        self.volumes = volumes
        self.lastVolume = lastVolume
    }

    public func volume(on deviceUID: String) -> AppVolume {
        volumes[deviceUID] ?? lastVolume ?? AppVolume()
    }

    /// Nothing differs from an app the mixer has never seen, so there is nothing to keep.
    public var isDefault: Bool {
        outputDeviceUID == nil && !(lastVolume?.needsRouting ?? false)
            && volumes.values.allSatisfy { !$0.needsRouting }
    }
}
