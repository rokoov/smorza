import Foundation

/// A saved mix to switch to in one go: each listed app's volume and mute, and whether apps the
/// profile leaves out are muted (a "Meeting" that silences everything but Zoom).
public struct Profile: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var apps: [String: AppVolume]
    public var mutesOtherApps: Bool

    public init(id: UUID = UUID(), name: String, apps: [String: AppVolume], mutesOtherApps: Bool = false) {
        self.id = id
        self.name = name
        self.apps = apps
        self.mutesOtherApps = mutesOtherApps
    }

    /// The settings each app gets when switching to this profile, given the mixer's apps now.
    /// Listed apps take the profile's values even while they are not running; apps left out are
    /// muted with `mutesOtherApps` and left alone without it.
    public func changes(from current: [String: AppVolume]) -> [String: AppVolume] {
        var changes = apps
        guard mutesOtherApps else { return changes }
        for (key, setting) in current where apps[key] == nil {
            var muted = setting
            muted.isMuted = true
            changes[key] = muted
        }
        return changes
    }
}
