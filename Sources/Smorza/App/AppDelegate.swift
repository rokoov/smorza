import AppIntents
import AppKit
import KeyboardShortcuts

/// Owns the model, the updater, the panel and the windows, so routing starts at launch rather than
/// when the panel first opens, and takes the routes down on the way out.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()
    let updater = Updater()
    let welcome = WelcomeWindow()
    private let previousApp = PreviousApp()
    private(set) var panel: MixerPanelController?
    private var settings: SettingsWindow?
    private var links: LinkHandler?
    /// Links that arrive while the app is still starting, as when one launches it.
    private var waitingLinks: [URL] = []
    private var signalSources: [DispatchSourceSignal] = []

    override init() {
        super.init()
        // The Shortcuts actions run in this process and reach the mixer through this.
        let model = model
        AppDependencyManager.shared.add(dependency: model)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isFirstLaunch = welcome.isFirstLaunch
        if isFirstLaunch {
            model.defersCaptureCheck = true
        }
        model.start()
        updater.start()
        NSApp.mainMenu = MainMenu.make(settingsAction: #selector(showSettings(_:)))
        settings = SettingsWindow { [unowned self] in
            SettingsView(model: model, updater: updater, onShowWelcome: { [unowned self] in welcome.show(for: model) })
        }
        let panel = MixerPanelController(
            content: MixerPanel(
                model: model,
                updater: updater,
                onOpenSettings: { [weak self] in self?.showSettings(nil) }
            )
        )
        panel.onVisibilityChange = { [model, previousApp] isVisible in
            if isVisible {
                model.panelDidAppear()
            } else {
                model.panelDidDisappear()
                previousApp.handBackIfIdle()
            }
        }
        self.panel = panel
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.panel?.toggle()
        }
        let links = LinkHandler(model: model, openPanel: { [weak self] in self?.panel?.show() })
        self.links = links
        waitingLinks.forEach(links.open)
        waitingLinks.removeAll()
        if isFirstLaunch {
            welcome.show(for: model)
        }
        quitThroughAppKit(on: [SIGTERM, SIGINT])
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let links else {
            waitingLinks += urls
            return
        }
        urls.forEach(links.open)
        if panel?.isShown != true {
            previousApp.handBackAfterLink()
        }
    }

    @objc func showSettings(_ sender: Any?) {
        // macOS lets an app come forward right after the user clicked it, which here means while
        // the panel they clicked is still open.
        settings?.show()
        panel?.close()
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
