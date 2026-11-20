/// Every app in the mixer muted at once, and what to put back when it ends.
public struct MuteAllSession: Equatable {
    /// Every app's mute from before.
    public let mutesBefore: [String: Bool]

    public init(mutesBefore: [String: Bool]) {
        self.mutesBefore = mutesBefore
    }

    public var mutes: [String: Bool] {
        mutesBefore.mapValues { _ in true }
    }
}
