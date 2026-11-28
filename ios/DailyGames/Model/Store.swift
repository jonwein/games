import Foundation
import Observation
import SwiftUI

/// What a pasted or caught result should do, worked out before anything changes.
enum Decision {
    case toast(String)
    case add(Game, text: String)
    case addNew(GameEntry, text: String, guess: GameEntry?)
    case pick(Pick)
}

/// A result whose game we have to ask about: a new one (name filled in with our guess) or one already listed.
struct Pick: Identifiable {
    let id = UUID()
    let text: String
    let guess: GameEntry?
    /// The likeliest games, which go first.
    let suggested: [Game]
    /// Whether adding it as a new game is the likelier answer.
    let newFirst: Bool
    /// What the new game's name starts as.
    var name: String

    init(text: String, guess: GameEntry?, suggested: [Game], newFirst: Bool) {
        self.text = text
        self.guess = guess
        self.suggested = suggested
        self.newFirst = newFirst
        name = guess?.name ?? ""
    }
}

/// A game just added for a result, which Change can take back off.
struct NewGame: Equatable {
    let gameID: String
    let text: String
    let guess: GameEntry?
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    /// A result went in.
    var success = false
    /// Offers Change, for a game that was just added.
    var newGame: NewGame?
}

enum Feedback {
    case toast(Toast)
    case pick(Pick)
}

/// Something wrong with an edit, and which field it's about.
struct EditError: Equatable {
    enum Field { case name, link }
    let field: Field
    let message: String
}

/// The game list and today's results, saved on this device.
@Observable
final class Store {
    private(set) var games: [Game]
    private(set) var day: Day
    /// The game last opened from the list. A result that doesn't say which game it's from probably came from it.
    var lastOpened: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date

    static let gamesKey = "dailygames:games:v1"
    static let dayKey = "dailygames:v1"

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
        let saved = (defaults.data(forKey: Self.gamesKey)).flatMap { try? JSONDecoder().decode([Game].self, from: $0) }
        games = saved?.filter { !JS.trim($0.name).isEmpty } ?? Game.starters
        let today = Self.dateString(clock())
        if let data = defaults.data(forKey: Self.dayKey), let day = try? JSONDecoder().decode(Day.self, from: data) {
            self.day = day.date == today ? day : day.rolledOver(to: today)
        } else {
            day = Day(date: today)
        }
    }

    // MARK: Saving

    private func saveGames() {
        if let data = try? JSONEncoder().encode(games) { defaults.set(data, forKey: Self.gamesKey) }
    }

    private func saveDay() {
        if let data = try? JSONEncoder().encode(day) { defaults.set(data, forKey: Self.dayKey) }
    }

    // MARK: Today

    static func dateString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var now: Date { clock() }

    /// Start a new day's list when the date has changed. Yesterday's results are kept aside as stale.
    func checkDay() {
        let today = Self.dateString(clock())
        guard day.date != today else { return }
        day = day.rolledOver(to: today)
        saveDay()
    }

    func result(for game: Game) -> String? { day.results[game.id] }
    var doneCount: Int { games.filter { day.results[$0.id] != nil }.count }
    var allDone: Bool { !games.isEmpty && doneCount == games.count }

    /// Everything played today, in list order, as one message.
    var message: String {
        games.compactMap { day.results[$0.id] }.map(Matching.inMessage).joined(separator: "\n\n")
    }

    func clearResult(_ game: Game) {
        day.results[game.id] = nil
        saveDay()
    }

    // MARK: Results

    private static let lineBreaks = Pattern("\r\n?")

    /// Which game a pasted or caught result belongs to, if we can tell.
    func decide(_ raw: String) -> Decision {
        let text = JS.trim(Self.lineBreaks.replaceAll(raw, with: "\n"))
        if text.isEmpty { return .toast("Clipboard is empty. Tap Share in the game first.") }

        // Compare without links, since the message we send has them stripped. A paste that contains another
        // game's saved result is the combined message copied back in, not a new result.
        let bare = Matching.stripLinks(text)
        func contains(_ saved: String) -> Bool { bare.contains(Matching.stripLinks(saved)) }
        if day.stale.contains(where: contains) { return .toast("That's an old result. Tap Share in the game first.") }

        // A result names its game on the first line. Further down a name can be just a hashtag ("Bandle #500 …
        // #Bandle #Heardle #Wordle"). A link into a listed game's page is as good as its name.
        let top = Matching.detect(Matching.headLine(text), in: games) ?? Matching.listedAt(Matching.findLink(text), in: games)
        let named = top.map { [$0] } ?? Matching.mentioned(text, in: games)
        let game = named.count == 1 ? named[0] : nil
        let saved = games.filter { g in day.results[g.id].map(contains) ?? false }
        if saved.contains(where: { day.results[$0.id].map(Matching.stripLinks) == bare }) {
            return .toast("Already added. Tap Share in the next game first.")
        }
        if saved.contains(where: { $0.id != game?.id }) { return .toast("That's your combined message. Tap Share in the game first.") }
        if let top { return .add(top, text: text) }

        let guess = Matching.guessGame(text)
        if let guess, let same = games.first(where: { $0.names.contains { $0.lowercased() == guess.name.lowercased() } }) ?? Matching.listedAt(guess.url, in: games) {
            return .add(same, text: text)
        }
        if let game, guess == nil { return .add(game, text: text) }
        // Not sure: the result names a listed game below a different title, or names several, or you just opened
        // a game from the list and haven't added its result yet. Otherwise it's a game that isn't listed yet.
        if !named.isEmpty { return .pick(Pick(text: text, guess: guess, suggested: named, newFirst: guess != nil && named.count == 1)) }
        if let opened = games.first(where: { $0.id == lastOpened && day.results[$0.id] == nil }) {
            return .pick(Pick(text: text, guess: guess, suggested: [opened], newFirst: false))
        }
        if let guess, Matching.looksLikeResult(text) { return .addNew(guess, text: text, guess: guess) }
        return .pick(Pick(text: text, guess: guess, suggested: [], newFirst: guess != nil))
    }

    /// Add a pasted or caught result, or say why not, or ask which game it's from.
    func handle(_ raw: String) -> Feedback {
        checkDay()
        switch decide(raw) {
        case .toast(let message): return .toast(Toast(message: message))
        case .add(let game, let text): return .toast(add(game, text))
        case .addNew(let entry, let text, let guess): return .toast(addNew(entry, text: text, guess: guess))
        case .pick(let pick): return .pick(pick)
        }
    }

    @discardableResult
    func add(_ game: Game, _ text: String) -> Toast {
        let replaced = day.results[game.id] != nil
        day.results[game.id] = text
        saveDay()
        let left = games.count - doneCount
        return Toast(message: "\(replaced ? "Updated" : "Added") \(game.name)" + (left > 0 ? " · \(left) to go" : " · all done!"), success: true)
    }

    /// Put a result's game at the end of the list, with the result. Change takes it back off and asks instead.
    func addNew(_ entry: GameEntry, text: String, guess: GameEntry?) -> Toast {
        let game = Game(id: newID(), name: entry.name, url: entry.url, alias: entry.alias)
        games.append(game)
        saveGames()
        day.results[game.id] = text
        saveDay()
        return Toast(message: "Added \(game.name) as a new game", success: true, newGame: NewGame(gameID: game.id, text: text, guess: guess))
    }

    /// Change: take back a game just added for a result, and ask which game the result is from.
    func undo(_ newGame: NewGame) -> Pick {
        var pick = Pick(text: newGame.text, guess: newGame.guess, suggested: [], newFirst: true)
        if let game = games.first(where: { $0.id == newGame.gameID }) { pick.name = game.name }
        games.removeAll { $0.id == newGame.gameID }
        day.results[newGame.gameID] = nil
        saveGames()
        saveDay()
        return pick
    }

    /// Picking a listed game for a result that doesn't name it teaches the game the name that result uses.
    func choose(_ game: Game, for pick: Pick) -> Toast {
        guard let i = games.firstIndex(where: { $0.id == game.id }) else { return Toast(message: "\(game.name) isn't on your list anymore.") }
        if let guess = pick.guess, !Matching.mentions(games[i], pick.text) {
            games[i].alias = guess.name
            saveGames()
        }
        return add(games[i], pick.text)
    }

    /// Add the result as a new game with this name, or to the listed game that has it. Nil when the name is blank.
    func addNamed(_ rawName: String, for pick: Pick) -> Toast? {
        let name = JS.trim(rawName)
        guard !name.isEmpty else { return nil }
        if let listed = games.first(where: { $0.name.lowercased() == name.lowercased() }) { return choose(listed, for: pick) }
        let guessed = pick.guess.flatMap { Matching.isSearch($0.url) ? nil : $0.url }
        var entry = GameEntry(name: name, url: guessed ?? Matching.urlFor(name, link: Matching.findLink(pick.text)))
        if let guess = pick.guess, !Matching.matcher(name).test(pick.text) { entry.alias = guess.name }
        return addNew(entry, text: pick.text, guess: pick.guess)
    }

    // MARK: Editing the list

    private func newID() -> String {
        var ms = Int(clock().timeIntervalSince1970 * 1000)
        while games.contains(where: { $0.id == "g" + String(ms, radix: 36) }) { ms += 1 }
        return "g" + String(ms, radix: 36)
    }

    /// Add a game from its link. Returns the message to show and whether it went in.
    func addGame(link: String, name rawName: String) -> (added: Bool, message: String) {
        guard let url = Matching.normalizeUrl(link) else { return (false, "That link doesn't look right.") }
        let typed = JS.trim(rawName)
        let name = typed.isEmpty ? Matching.nameFromUrl(url) : typed
        if name.isEmpty { return (false, "Give it a name.") }
        if games.contains(where: { $0.name.lowercased() == name.lowercased() }) { return (false, "\(name) is already on your list.") }
        games.append(Game(id: newID(), name: name, url: url))
        saveGames()
        return (true, "Added \(name)")
    }

    private static let spaces = Pattern(JS.space + "+")

    /// Change a listed game's name or link. An empty link means Play searches for the game.
    func updateGame(_ id: String, name rawName: String, link rawLink: String) -> EditError? {
        guard let i = games.firstIndex(where: { $0.id == id }) else { return nil }
        var g = games[i]
        let name = Self.spaces.replaceAll(JS.trim(rawName), with: " ")
        if name.isEmpty { return EditError(field: .name, message: "Give it a name.") }
        if games.contains(where: { $0.id != id && $0.name.lowercased() == name.lowercased() }) {
            return EditError(field: .name, message: "\(name) is already on your list.")
        }
        let raw = JS.trim(rawLink)
        guard let url = raw.isEmpty ? Matching.searchURL(for: name) : raw == g.url ? g.url : Matching.normalizeUrl(raw) else {
            return EditError(field: .link, message: "That link doesn't look right.")
        }
        // Results are matched by name, so a renamed game keeps answering to its old one ("Krillion" results
        // still count after renaming it "Krill"), unless it already knows the name its results use.
        if name.lowercased() != g.name.lowercased() && g.alias == nil { g.alias = g.name }
        if let alias = g.alias, alias.lowercased() == name.lowercased() { g.alias = nil }
        g.name = name
        g.url = url
        games[i] = g
        saveGames()
        return nil
    }

    func moveGames(from source: IndexSet, to destination: Int) {
        games.move(fromOffsets: source, toOffset: destination)
        saveGames()
    }

    func deleteGames(at offsets: IndexSet) {
        games.remove(atOffsets: offsets)
        saveGames()
    }

    /// Starter games that aren't on the list, so they can be added back with one tap.
    var suggestions: [Game] {
        func same(_ a: Game, _ b: Game) -> Bool {
            a.names.contains { n in b.names.contains { $0.lowercased() == n.lowercased() } }
        }
        return Game.starters.filter { d in !games.contains { $0.id == d.id || same($0, d) } }
    }

    func addSuggestion(_ game: Game) {
        games.append(game)
        saveGames()
    }
}
