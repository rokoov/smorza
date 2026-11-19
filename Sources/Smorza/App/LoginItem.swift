import Observation
import ServiceManagement

/// "Open at login", through the system's Login Items.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var error: String?

    init() { refresh() }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }
}
