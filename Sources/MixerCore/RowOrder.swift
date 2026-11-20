import Foundation

/// Something the mixer shows as a row: an app with a name that may be playing or pinned.
public protocol MixerRowItem {
    var id: String { get }
    var name: String { get }
    var isPlaying: Bool { get }
    var isPinned: Bool { get }
}

/// The order of the mixer's rows.
public enum RowOrder {
    /// Apps making sound first, where the hand goes most often, then pinned apps, then the rest
    /// by when they last played (from `lastPlayed`), each group by name. Given the ids already on
    /// screen, those keep their places and new rows join at the end, so nothing moves under the
    /// pointer while the panel is open.
    public static func arrange<Row: MixerRowItem>(
        _ rows: [Row],
        lastPlayed: [String: Date] = [:],
        keepingPlacesOf onScreen: [String]? = nil
    ) -> [Row] {
        let ordered = rows.sorted { precedes($0, $1, lastPlayed: lastPlayed) }
        guard let onScreen else { return ordered }
        let places = Dictionary(onScreen.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let kept =
            ordered
            .filter { places[$0.id] != nil }
            .sorted { places[$0.id, default: 0] < places[$1.id, default: 0] }
        return kept + ordered.filter { places[$0.id] == nil }
    }

    private static func precedes<Row: MixerRowItem>(_ first: Row, _ second: Row, lastPlayed: [String: Date]) -> Bool {
        if first.isPlaying != second.isPlaying { return first.isPlaying }
        if !first.isPlaying {
            if first.isPinned != second.isPinned { return first.isPinned }
            if !first.isPinned {
                let firstPlayed = lastPlayed[first.id] ?? .distantPast
                let secondPlayed = lastPlayed[second.id] ?? .distantPast
                if firstPlayed != secondPlayed { return firstPlayed > secondPlayed }
            }
        }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }
}
