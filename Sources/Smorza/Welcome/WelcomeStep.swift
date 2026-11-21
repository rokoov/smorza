/// Where the welcome window is: the explanation, the macOS permission dialog, a refusal, or done.
enum WelcomeStep: CaseIterable {
    case intro
    case waiting
    case denied
    case done

    /// The step the capture check's state puts the window on, once the user pressed Continue.
    init(captureState: CaptureCheckController.State) {
        switch captureState {
        case .unknown, .checking: self = .waiting
        case .allowed: self = .done
        case .blocked: self = .denied
        }
    }
}
