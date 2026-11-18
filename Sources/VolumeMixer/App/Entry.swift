import AppKit

/// Starts the menu bar app, or runs one of the debugging commands instead.
@main
enum Entry {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--list") {
            Diagnostics.printAudioClients()
            return
        }
        for (option, demo) in [("--snapshot", false), ("--snapshot-demo", true)] {
            if let flag = arguments.firstIndex(of: option), arguments.indices.contains(flag + 1) {
                PanelSnapshot.write(to: arguments[flag + 1], demo: demo)
                return
            }
        }
        VolumeMixerApp.main()
    }
}
