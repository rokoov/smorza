import AppKit
import SwiftUI

/// Reports whether the window holding this view is on screen. A MenuBarExtra keeps its content
/// alive between openings, so onAppear and onDisappear cannot mark every open and close.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = onChange
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observation: NSObjectProtocol?
        private var isVisible: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observation {
                NotificationCenter.default.removeObserver(observation)
            }
            observation = nil
            guard let window else {
                report(false)
                return
            }
            observation = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportWindowState() }
            }
            reportWindowState()
        }

        private func reportWindowState() {
            report(window?.occlusionState.contains(.visible) ?? false)
        }

        private func report(_ visible: Bool) {
            guard visible != isVisible else { return }
            isVisible = visible
            onChange?(visible)
        }
    }
}
