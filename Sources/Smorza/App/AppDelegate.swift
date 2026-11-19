import AppKit

/// Owns the model and the updater, so routing starts at launch rather than when the panel first
/// opens, and takes the routes down on the way out.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()
    let updater = Updater()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        updater.start()
        quitThroughAppKit(on: [SIGTERM, SIGINT])
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutDown()
    }

    /// A plain SIGTERM (`kill`, a logout that times out) would end the process without
    /// `applicationWillTerminate`, leaving its routes for coreaudiod to clean up.
    private func quitThroughAppKit(on signals: [Int32]) {
        for signalNumber in signals {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
