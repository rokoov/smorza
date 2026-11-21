import AppKit

/// Repeats a shortcut's action while its keys are held, at the keyboard's own repeat delay and
/// rate: Carbon hot keys only report the press and the release.
@MainActor
final class HeldKey {
    /// Stops a repeat whose release never arrived; a full sweep of the volume takes twenty steps.
    private static let maximumRepeats = 40

    private var repeats: Task<Void, Never>?

    /// Runs `action` now and again while held, until it returns false or the keys come up.
    func press(_ action: @escaping @MainActor () -> Bool) {
        repeats?.cancel()
        guard action() else { return }
        repeats = Task {
            try? await Task.sleep(for: .seconds(NSEvent.keyRepeatDelay))
            for _ in 0..<Self.maximumRepeats {
                guard !Task.isCancelled, action() else { return }
                try? await Task.sleep(for: .seconds(NSEvent.keyRepeatInterval))
            }
        }
    }

    func release() {
        repeats?.cancel()
        repeats = nil
    }
}
