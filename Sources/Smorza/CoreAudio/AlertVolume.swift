import AppKit
import Observation

/// The volume of alert and notification sounds, the Alert volume in System Settings > Sound.
/// macOS keeps it behind AppleScript's volume settings, which run inside this app and need no
/// permission. It has no mute of its own, so muting sets it to 0 and remembers the level.
@MainActor
@Observable
final class AlertVolume {
    /// Where the level before a mute is kept, so unmuting works after a relaunch too.
    private static let levelBeforeMuteKey = "AlertVolumeBeforeMute"
    /// Unmuting brings back this level when there is none to go back to.
    private static let unmutedLevel = 50

    /// 0...100, as System Settings shows it.
    private(set) var percent = 100
    @ObservationIgnored private let readScript = NSAppleScript(source: "alert volume of (get volume settings)")

    var volume: Double { Double(percent) / 100 }
    var isMuted: Bool { percent == 0 }

    /// Reads the level again: System Settings may have changed it.
    func refresh() {
        var error: NSDictionary?
        guard let result = readScript?.executeAndReturnError(&error) else {
            log.error("Could not read the alert volume: \(String(describing: error), privacy: .public)")
            return
        }
        percent = min(max(Int(result.int32Value), 0), 100)
    }

    func setVolume(_ value: Double) {
        write(Int((min(max(value, 0), 1) * 100).rounded()))
    }

    func toggleMute() {
        if isMuted {
            let before = UserDefaults.standard.integer(forKey: Self.levelBeforeMuteKey)
            write(before > 0 ? before : Self.unmutedLevel)
        } else {
            UserDefaults.standard.set(percent, forKey: Self.levelBeforeMuteKey)
            write(0)
        }
    }

    private func write(_ level: Int) {
        guard level != percent else { return }
        var error: NSDictionary?
        NSAppleScript(source: "set volume alert volume \(level)")?.executeAndReturnError(&error)
        if let error {
            log.error("Could not set the alert volume: \(String(describing: error), privacy: .public)")
            return
        }
        percent = level
    }
}
