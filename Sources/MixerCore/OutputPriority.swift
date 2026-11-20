import Foundation

/// The user's order of output devices: the first one connected becomes the default output, and each
/// device keeps its own system volume. Off until the user turns it on, so macOS's own choice stands.
public struct OutputPriority: Codable, Equatable {
    public struct Device: Codable, Equatable {
        public let uid: String
        /// The device's name, to show while it is not connected.
        public var name: String

        public init(uid: String, name: String) {
            self.uid = uid
            self.name = name
        }
    }

    public var isEnabled: Bool
    /// Most wanted first. A device joins at the end the first time it is seen.
    public private(set) var devices: [Device]
    /// Each device's own system volume, by UID.
    public var volumes: [String: Double]

    public init(isEnabled: Bool = false, devices: [Device] = [], volumes: [String: Double] = [:]) {
        self.isEnabled = isEnabled
        self.devices = devices
        self.volumes = volumes
    }

    /// The device that should be the default output: the first connected one in the list. Nil while
    /// switching is off or no listed device is connected.
    public func preferredDevice(among connected: Set<String>) -> String? {
        guard isEnabled else { return nil }
        return devices.first { connected.contains($0.uid) }?.uid
    }

    /// Adds devices seen for the first time at the end and keeps the names of known ones current.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func learn(_ seen: [Device]) -> Bool {
        let before = devices
        for device in seen {
            if let index = devices.firstIndex(where: { $0.uid == device.uid }) {
                devices[index].name = device.name
            } else {
                devices.append(device)
            }
        }
        return devices != before
    }

    /// Moves a device up (negative) or down (positive) the list, stopping at either end.
    public mutating func move(_ uid: String, by offset: Int) {
        guard let index = devices.firstIndex(where: { $0.uid == uid }) else { return }
        let target = min(max(index + offset, 0), devices.count - 1)
        guard target != index else { return }
        devices.insert(devices.remove(at: index), at: target)
    }

    public mutating func forget(_ uid: String) {
        devices.removeAll { $0.uid == uid }
        volumes[uid] = nil
    }
}
