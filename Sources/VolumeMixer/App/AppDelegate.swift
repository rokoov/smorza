import AppKit

/// Owns the model, so routing starts at launch rather than when the panel first opens.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}
