import Foundation

/// The app that the shortcuts for one app and the volume keys change: the one that started
/// playing most recently, or the app in front when nothing plays.
public enum TargetApp {
    /// `playingSince` holds when each playing app started. Apps found playing together, as at
    /// launch, have the same start: the app in front wins among them, otherwise the first key in
    /// order, so the choice never flips between them.
    public static func choose(playingSince: [String: Date], frontmost: String?) -> String? {
        guard let latest = playingSince.values.max() else { return frontmost }
        let newest = playingSince.filter { $0.value == latest }.keys
        if let frontmost, newest.contains(frontmost) {
            return frontmost
        }
        return newest.min()
    }
}
