import AppKit
import SwiftUI

@main
enum Entry {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--list") {
            Diagnostics.printAudioClients()
            return
        }
        if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
            Diagnostics.writeSnapshots(to: arguments[flag + 1])
            return
        }
        VolumeMixerApp.main()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}

struct VolumeMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MixerPanel(model: appDelegate.model)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .accessibilityLabel("Volume Mixer")
        }
        .menuBarExtraStyle(.window)
    }
}
