import AppKit
import Darwin
import UniformTypeIdentifiers

/// The app a row in the mixer stands for. Every process with the same key shares one slider.
struct AppIdentity: Equatable {
    let key: String
    let name: String
    let icon: NSImage
}

/// Names the app behind an audio client. Browsers and WebKit play sound from helper processes
/// (Safari's comes from com.apple.WebKit.GPU), so a helper is credited to the app macOS holds
/// responsible for it.
@MainActor
final class AppResolver {
    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t

    // Private libsystem call; without it helpers simply show under their own names.
    private static let responsiblePID: ResponsiblePID? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePID.self)
    }()

    private static let genericIcon = NSWorkspace.shared.icon(for: .unixExecutable)

    private var cache: [pid_t: AppIdentity] = [:]

    func identity(for client: AudioClient) -> AppIdentity {
        if let cached = cache[client.pid] { return cached }
        let identity = resolve(pid: client.pid, bundleID: client.bundleID)
        cache[client.pid] = identity
        return identity
    }

    func forget(allBut alive: Set<pid_t>) {
        cache = cache.filter { alive.contains($0.key) }
    }

    private func resolve(pid: pid_t, bundleID: String?) -> AppIdentity {
        let own = NSRunningApplication(processIdentifier: pid)
        if let own, own.activationPolicy == .regular {
            return Self.identity(of: own)
        }
        // Only bundled helpers are credited to their owner; a command line tool such as afplay
        // keeps its own name instead of turning into the terminal that started it.
        if bundleID != nil, let owner = Self.responsibleApp(for: pid) {
            return Self.identity(of: owner)
        }
        if let own, own.localizedName != nil {
            return Self.identity(of: own)
        }
        let name = bundleID.flatMap { Self.systemNames[$0] } ?? Self.processName(pid) ?? bundleID ?? "Process \(pid)"
        return AppIdentity(key: bundleID ?? "process:\(name)", name: name, icon: Self.genericIcon)
    }

    /// Daemons that play sound the user recognises, under a readable name.
    private static let systemNames = [
        "systemsoundserverd": "System Sounds",
        "com.apple.PowerChime": "Charging Sound",
    ]

    private static func responsibleApp(for pid: pid_t) -> NSRunningApplication? {
        guard let responsiblePID else { return nil }
        let ownerPID = responsiblePID(pid)
        guard ownerPID > 0, ownerPID != pid,
            let owner = NSRunningApplication(processIdentifier: ownerPID),
            owner.activationPolicy == .regular
        else { return nil }
        return owner
    }

    private static func identity(of app: NSRunningApplication) -> AppIdentity {
        let name = app.localizedName ?? app.bundleIdentifier ?? "Process \(app.processIdentifier)"
        return AppIdentity(key: app.bundleIdentifier ?? "process:\(name)", name: name, icon: app.icon ?? genericIcon)
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
