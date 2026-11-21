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
        /// A check that takes this long to start was waiting on the macOS prompt; without one it starts
        /// in a fraction of a second.
        static let promptWait: Duration = .seconds(1)
        /// Once the user answered the prompt, the check hears the signal within this time if they
        /// allowed it; a check passes in about 1.5 s.
        static let answerWait: Duration = .seconds(4)
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
    /// The output device changed under a running check, which rebuilds itself on the new one.
    @ObservationIgnored private var needsRestart = false

    var isRunning: Bool { task != nil }

    func begin(on device: AudioObjectID) {
        guard state == .unknown, task == nil, device.isKnown else { return }
        self.device = device
        state = .checking
        log.notice("Checking that macOS lets the mixer hear other apps")
        task = Task { [weak self] in
            await self?.run(since: .now)
        }
    }

    /// Lets a failed check run again, after the user touched a slider or pressed Try Again.
    func retry() {
        guard state == .blocked else { return }
        state = .unknown
    }

    func outputDeviceChanged(to device: AudioObjectID) {
        self.device = device
        if task != nil {
            needsRestart = true
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
        guard task != nil || check != nil else { return }
        check?.abandon()
        check = nil
        task?.cancel()
        task = nil
        state = .unknown
    }

    private func run(since started: ContinuousClock.Instant) async {
        let didStart = await startCheck()
        // macOS holds the first check until the user answers its prompt, so a check this slow to
        // start comes with the answer: the signal arrives within seconds if they allowed it, and
        // failing or staying silent is a refusal. Otherwise the user still has the full timeout.
        let answeredPrompt = ContinuousClock.now - started >= Timing.promptWait
        guard didStart else {
            if answeredPrompt, !Task.isCancelled {
                finish(allowed: false, after: ContinuousClock.now - started)
                return
            }
            // Nothing to listen with (a HAL error): the next sync of the routes tries again.
            task = nil
            state = .unknown
            return
        }
        let deadline = answeredPrompt ? ContinuousClock.now + Timing.answerWait : started + Timing.timeout
        var lastStart = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: Timing.poll)
            guard !Task.isCancelled else { return }
            let now = ContinuousClock.now
            if check?.hasHeardSignal == true {
                finish(allowed: true, after: now - started)
                return
            }
            if now >= deadline {
                finish(allowed: false, after: now - started)
                return
            }
            if needsRestart || now - lastStart >= Timing.restart {
                await restartCheck()
                lastStart = ContinuousClock.now
            }
        }
    }

    @discardableResult
    private func startCheck() async -> Bool {
        let device = device
        let result = await HALQueue.run { Result { try CaptureCheck(outputDevice: device) } }
        guard !Task.isCancelled else {
            // Shut down or abandoned while the check was being built.
            if case .success(let check) = result {
                await HALQueue.run { check.invalidate() }
            }
            return false
        }
        switch result {
        case .success(let check):
            self.check = check
            lastError = nil
            return true
        case .failure(let error):
            lastError = "Audio check: \(error.localizedDescription)"
            log.error("Capture check could not start: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func restartCheck() async {
        needsRestart = false
        if let old = check {
            check = nil
            await HALQueue.run { old.invalidate() }
        }
        guard !Task.isCancelled else { return }
        await startCheck()
    }

    private func finish(allowed: Bool, after elapsed: Duration) {
        task = nil
        if let old = check {
            check = nil
            Task { await HALQueue.run { old.invalidate() } }
        }
        state = allowed ? .allowed : .blocked
        wasBlocked = !allowed
        let duration = elapsed.formatted(.units(allowed: [.seconds, .milliseconds]))
        log.notice(
            "Capture check \(allowed ? "passed" : "failed", privacy: .public) after \(duration, privacy: .public)"
        )
        onFinish?()
    }
}
