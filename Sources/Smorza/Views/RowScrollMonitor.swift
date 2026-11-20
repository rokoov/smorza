import AppKit

/// Watches scrolling in this app's windows while the panel shows, so a row can take the scroll
/// that happens over it. Everything else passes on untouched.
@MainActor
final class RowScrollMonitor {
    private var monitor: Any?

    /// `handler` gets every scroll event and returns true when it used it, which keeps it from the
    /// window.
    func start(_ handler: @escaping @MainActor (NSEvent) -> Bool) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Local monitors run on the main thread.
            let isUsed = MainActor.assumeIsolated { handler(event) }
            return isUsed ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
