/// One app playing solo: which apps to mute when it starts, and what to put back when it ends.
public struct SoloSession: Equatable {
    public let key: String
    /// Every app's mute from before the solo started.
    public let mutesBefore: [String: Bool]

    public init(key: String, mutesBefore: [String: Bool]) {
        self.key = key
        self.mutesBefore = mutesBefore
    }

    /// Every other app muted and the solo app unmuted.
    public var mutes: [String: Bool] {
        var mutes = mutesBefore.mapValues { _ in true }
        mutes[key] = false
        return mutes
    }
}
