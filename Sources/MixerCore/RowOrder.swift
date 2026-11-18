import Foundation

/// Something the mixer shows as a row: an app with a name that may be playing.
public protocol MixerRowItem {
    var id: String { get }
    var name: String { get }
    var isPlaying: Bool { get }
}

/// The order of the mixer's rows.
public enum RowOrder {
    /// Apps making sound first, where the hand goes most often, then by name. Given the ids already
    /// on screen, those keep their places and new rows join at the end, so nothing moves under the
    /// pointer while the panel is open.
    public static func arrange<Row: MixerRowItem>(_ rows: [Row], keepingPlacesOf onScreen: [String]? = nil) -> [Row] {
        let byActivity = rows.sorted(by: playingFirst)
        guard let onScreen else { return byActivity }
        let places = Dictionary(onScreen.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let kept =
            byActivity
            .filter { places[$0.id] != nil }
            .sorted { places[$0.id, default: 0] < places[$1.id, default: 0] }
        return kept + byActivity.filter { places[$0.id] == nil }
    }

    private static func playingFirst<Row: MixerRowItem>(_ first: Row, _ second: Row) -> Bool {
        if first.isPlaying != second.isPlaying { return first.isPlaying }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }
}
