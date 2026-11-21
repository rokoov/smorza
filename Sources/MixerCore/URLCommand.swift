import Foundation

/// A smorza:// link, as Terminal, Raycast or the Shortcuts Open URL action open it. The action is
/// the host and the rest are query parameters, as in `smorza://set-volume?app=com.spotify.client&volume=40`.
/// Each `app` parameter names an app by bundle identifier, so one link can change several.
public enum URLCommand: Equatable, Sendable {
    case setVolume(apps: [String], percent: Double)
    /// One step up (`direction` 1) or down (-1).
    case stepVolume(apps: [String], direction: Int)
    case mute(apps: [String], change: MuteChange)
    /// `device` is a device's name or UID, or `default` for the system output.
    case setOutput(apps: [String], device: String)
    case muteAll(MuteChange)
    /// Every app back to 100%, unmuted, on the system output.
    case reset
    case open

    public static let scheme = "smorza"

    /// Why a link does nothing, for the log.
    public struct Rejection: Error, Equatable, CustomStringConvertible {
        public let description: String

        init(_ description: String) {
            self.description = description
        }
    }

    public static func parse(_ url: URL) -> Result<URLCommand, Rejection> {
        do {
            return .success(try command(from: url))
        } catch {
            return .failure(error)
        }
    }

    private static func command(from url: URL) throws(Rejection) -> URLCommand {
        guard url.scheme?.lowercased() == scheme,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw Rejection("not a smorza:// link") }
        let action = (components.host ?? components.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        let query = Query(components)
        switch action {
        case "", "open":
            return .open
        case "reset":
            return .reset
        case "mute-all":
            return .muteAll(try query.muteChange())
        case "mute":
            return .mute(apps: try query.apps(), change: try query.muteChange())
        case "set-volume":
            return .setVolume(apps: try query.apps(), percent: try query.percent())
        case "step-volume":
            return .stepVolume(apps: try query.apps(), direction: try query.direction())
        case "set-output":
            guard let device = try query.value("device") else { throw Rejection("no device given") }
            return .setOutput(apps: try query.apps(), device: device)
        default:
            throw Rejection("unknown action \"\(action)\"")
        }
    }
}

/// A link's parameters, read like a web form: `+` is a space and `%2B` a plus.
private struct Query {
    private let items: [(name: String, value: String)]

    init(_ components: URLComponents) {
        items = (components.percentEncodedQueryItems ?? []).map { item in
            let encoded = (item.value ?? "").replacingOccurrences(of: "+", with: " ")
            let value = (encoded.removingPercentEncoding ?? encoded).trimmingCharacters(in: .whitespaces)
            return (item.name.lowercased(), value)
        }
    }

    func value(_ name: String) throws(URLCommand.Rejection) -> String? {
        let found = values(name)
        guard found.count <= 1 else { throw URLCommand.Rejection("\(name) is given \(found.count) times") }
        return found.first
    }

    /// Every app named, each once.
    func apps() throws(URLCommand.Rejection) -> [String] {
        var seen: Set<String> = []
        let apps = values("app").filter { seen.insert($0.lowercased()).inserted }
        guard !apps.isEmpty else { throw URLCommand.Rejection("no app given") }
        return apps
    }

    func percent() throws(URLCommand.Rejection) -> Double {
        guard let text = try value("volume") else { throw URLCommand.Rejection("no volume given") }
        guard let percent = Double(text), (0...100).contains(percent) else {
            throw URLCommand.Rejection("volume must be a number from 0 to 100, not \"\(text)\"")
        }
        return percent
    }

    func direction() throws(URLCommand.Rejection) -> Int {
        switch try value("direction")?.lowercased() {
        case "up": return 1
        case "down": return -1
        case nil: throw URLCommand.Rejection("no direction given")
        case let other?: throw URLCommand.Rejection("direction must be up or down, not \"\(other)\"")
        }
    }

    /// Toggles when `muted` is left out, like the Shortcuts action.
    func muteChange() throws(URLCommand.Rejection) -> MuteChange {
        guard let text = try value("muted") else { return .toggle }
        switch text.lowercased() {
        case "true", "yes", "1": return .mute
        case "false", "no", "0": return .unmute
        case "toggle": return .toggle
        default: throw URLCommand.Rejection("muted must be true, false or toggle, not \"\(text)\"")
        }
    }

    private func values(_ name: String) -> [String] {
        items.filter { $0.name == name && !$0.value.isEmpty }.map(\.value)
    }
}
