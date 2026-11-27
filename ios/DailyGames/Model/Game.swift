import Foundation

/// A game on the list.
struct Game: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Where Play goes. A game with no link of its own gets a web search for its name.
    var url: String
    /// The name its results use, when that isn't `name`. It's learned when you pick the game for a result that
    /// doesn't name it, and kept when you rename a game so its results still match.
    var alias: String?

    var names: [String] { alias.map { [name, $0] } ?? [name] }

    /// New lists start with these. Everyone can add, remove, and reorder their own list from Edit.
    static let starters: [Game] = [
        Game(id: "perceptle", name: "Perceptle", url: "https://perceptle.com"),
        Game(id: "dailytens", name: "Daily Tens", url: "https://dailytens.com"),
        Game(id: "songless", name: "Songless", url: "https://lessgames.com/songless"),
        Game(id: "spotle", name: "Spotle", url: "https://spotle.io"),
        Game(id: "krillion", name: "Krillion", url: "https://krillion.io"),
        Game(id: "nytmini", name: "NYT Mini", url: "https://www.nytimes.com/crosswords/game/mini", alias: "Mini"),
    ]
}

/// A game that isn't on the list yet: a guess made from a result, or one about to be added.
struct GameEntry: Codable, Hashable {
    var name: String
    var url: String
    var alias: String?
}

/// Today's results, by game ID.
struct Day: Codable, Equatable {
    /// "2026-11-27", in local time.
    var date: String
    var results: [String: String] = [:]
    /// Yesterday's results, kept so an old result still sitting on the clipboard can be caught.
    var stale: [String] = []

    func rolledOver(to date: String) -> Day {
        Day(date: date, results: [:], stale: Array(results.values))
    }
}
