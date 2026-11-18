import CoreAudio
import Foundation
import Observation

/// Whether macOS lets the mixer hear other apps (System Audio Recording), proven by a
/// `CaptureCheck` before any app is muted.
@MainActor
@Observable
final class CaptureCheckController {
    enum State: Equatable {
        /// Not checked yet, or a failed check is being retried.
        case unknown
        case checking
        case allowed
        case blocked
    }

    enum Timing {
        /// How often a running check looks for its signal.
        static let poll: Duration = .milliseconds(100)
        /// A check is rebuilt this often: one started while macOS was still asking may keep
        /// hearing silence after the user allowed it.
        static let restart: Duration = .seconds(5)
        /// How long the user has to answer the macOS prompt before the notice shows.
        static let timeout: Duration = .seconds(30)
    }

    private(set) var state = State.unknown
    /// Keeps the notice up while a retry runs after a failed check.
    private(set) var wasBlocked = false
    private(set) var lastError: String?
    /// Called when a check passes or fails.
    @ObservationIgnored var onFinish: (() -> Void)?

    @ObservationIgnored private var check: CaptureCheck?
    @ObservationIgnored private var device = AudioObjectID.unknown
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { check != nil }

    func begin(on device: AudioObjectID) {
        guard state == .unknown, check == nil else { return }
        self.device = device
        guard startCheck() else { return }
        state = .checking
        log.notice("Checking that macOS lets the mixer hear other apps")
        task = Task { [weak self] in
            await self?.watch(since: .now)
        }
    }

    /// Lets a failed check run again, after the user touched a slider or pressed Try Again.
    func retry() {
        guard state == .blocked else { return }
        state = .unknown
    }

    func outputDeviceChanged(to device: AudioObjectID) {
        self.device = device
        if check != nil {
            restartCheck()
        }
    }

    /// Stops a running check, for when the mixer quits.
    func shutDown() {
        task?.cancel()
        task = nil
        check?.invalidate()
        check = nil
    }

    /// Drops a running check without touching it, for after coreaudiod restarted.
    func abandon() {
        guard let check else { return }
        check.abandon()
        self.check = nil
        task?.cancel()
        task = nil
        state = .unknown
    }

    private func watch(since started: ContinuousClock.Instant) async {
        var lastStart = started
        while !Task.isCancelled {
            try? await Task.sleep(for: Timing.poll)
            guard !Task.isCancelled else { return }
            let now = ContinuousClock.now
            if check?.hasHeardSignal == true {
                finish(allowed: true, after: now - started)
                return
            }
            if now - started >= Timing.timeout {
                finish(allowed: false, after: now - started)
                return
            }
            if now - lastStart >= Timing.restart {
                lastStart = now
                restartCheck()
            }
        }
    }

    @discardableResult
    private func startCheck() -> Bool {
        guard device.isKnown else { return false }
        do {
            check = try CaptureCheck(outputDevice: device)
            lastError = nil
            return true
        } catch {
            lastError = "Audio check: \(error.localizedDescription)"
            log.error("Capture check could not start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func restartCheck() {
        check?.invalidate()
        check = nil
        startCheck()
    }

    private func finish(allowed: Bool, after elapsed: Duration) {
        task = nil
        check?.invalidate()
        check = nil
        state = allowed ? .allowed : .blocked
        wasBlocked = !allowed
        let duration = elapsed.formatted(.units(allowed: [.seconds, .milliseconds]))
        log.notice(
            "Capture check \(allowed ? "passed" : "failed", privacy: .public) after \(duration, privacy: .public)"
        )
        onFinish?()
    }
}
