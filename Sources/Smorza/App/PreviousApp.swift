import AppKit

/// The app the user was in before Smorza came to the front. A link brings Smorza forward even
/// when it only changes a volume, and Smorza in front with no window open leaves the keyboard
/// with nothing to type into, so it goes back to that app.
@MainActor
final class PreviousApp {
    private var app = NSWorkspace.shared.frontmostApplication
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .processIdentifier
                MainActor.assumeIsolated { self?.activated(pid) }
            }
        )
        // Closing the last Smorza window would otherwise leave Smorza in front.
        observers.append(
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    DispatchQueue.main.async { self?.handBackIfIdle() }
                }
            }
        )
    }

    /// After a link: Launch Services has just made Smorza active.
    func handBackAfterLink() {
        guard NSApp.isActive else { return }
        handBack()
    }

    /// After a window or the panel closed, when nothing else took the keyboard first.
    func handBackIfIdle() {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        else { return }
        handBack()
    }

    private func handBack() {
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }),
            let app, !app.isTerminated
        else { return }
        log.notice("Handing the keyboard back to \(app.localizedName ?? "the app before", privacy: .public)")
        app.activate()
    }

    private func activated(_ pid: pid_t?) {
        guard let pid, pid != ProcessInfo.processInfo.processIdentifier,
            let running = NSRunningApplication(processIdentifier: pid)
        else { return }
        app = running
    }
}
