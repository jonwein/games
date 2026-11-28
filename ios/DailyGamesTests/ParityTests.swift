import Foundation
import Testing
@testable import DailyGames

/// Checks the Swift matching reads results exactly as the web version does. Fixtures/parity.json holds the web
/// version's answers; regenerate it with `node ios/Tools/make_fixtures.mjs` after changing index.html.
@MainActor
struct ParityTests {
    struct Fixture: Decodable {
        struct Text: Decodable {
            let name: String
            let text: String
            let headLine: String
            let findLink: String?
            let titleOf: String?
            let guessGame: GameEntry?
            let looksLikeResult: Bool
            let stripLinks: String
            let mentioned: [String]
            let sharedTime: String?
            let inMessage: [String]
        }

        struct Link: Decodable {
            let input: String
            let normalizeUrl: String?
            let nameFromUrl: String?
        }

        struct Matcher: Decodable {
            let name: String
            let text: String
            let matches: Bool
        }

        struct Scenario: Decodable {
            struct Outcome: Decodable {
                let kind: String
                let game: String?
                let entry: GameEntry?
                let guess: GameEntry?
                let suggested: [String]?
                let newFirst: Bool?
                let message: String?
            }

            let name: String
            let games: [Game]?
            let results: [String: String]
            let stale: [String]
            let lastOpened: String?
            let text: String
            let outcome: Outcome
        }

        let defaults: [Game]
        let messageGames: [Game]
        let texts: [Text]
        let urls: [Link]
        let matchers: [Matcher]
        let scenarios: [Scenario]
    }

    let fixture: Fixture

    init() throws {
        // In the test bundle, or next to this file when the tests run some other way.
        let url = Bundle(for: BundleToken.self).url(forResource: "parity", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/parity.json")
        fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func starterGamesMatch() {
        #expect(fixture.defaults == Game.starters)
    }

    @Test func readsTextsTheSame() {
        for t in fixture.texts {
            let c = Comment(rawValue: t.name)
            #expect(Matching.headLine(t.text) == t.headLine, c)
            #expect(Matching.findLink(t.text) == t.findLink, c)
            #expect(Matching.titleOf(t.headLine) == t.titleOf, c)
            #expect(Matching.guessGame(t.text) == t.guessGame, c)
            #expect(Matching.looksLikeResult(t.text) == t.looksLikeResult, c)
            #expect(Matching.stripLinks(t.text) == t.stripLinks, c)
            #expect(Matching.mentioned(t.text, in: fixture.defaults).map(\.id) == t.mentioned, c)
            #expect(Matching.sharedTime(t.text) == t.sharedTime, c)
            #expect(fixture.messageGames.map { Matching.inMessage($0, t.text) } == t.inMessage, c)
        }
    }

    @Test func readsLinksTheSame() {
        for link in fixture.urls {
            let c = Comment(rawValue: link.input)
            let normalized = Matching.normalizeUrl(link.input)
            #expect(normalized == link.normalizeUrl, c)
            #expect(normalized.map(Matching.nameFromUrl) == link.nameFromUrl, c)
        }
    }

    @Test func matchesNamesTheSame() {
        for m in fixture.matchers {
            #expect(Matching.matcher(m.name).test(m.text) == m.matches, Comment(rawValue: "\(m.name) in \(m.text)"))
        }
    }

    @Test func decidesTheSame() throws {
        for s in fixture.scenarios {
            let c = Comment(rawValue: s.name)
            let store = try Self.store(games: s.games ?? fixture.defaults, results: s.results, stale: s.stale)
            store.lastOpened = s.lastOpened
            let o = s.outcome
            switch store.decide(s.text) {
            case .toast(let message):
                #expect(o.kind == "toast", c)
                #expect(message == o.message, c)
            case .add(let game, _):
                #expect(o.kind == "add", c)
                #expect(game.id == o.game, c)
            case .addNew(let entry, _, let guess):
                #expect(o.kind == "addNew", c)
                #expect(entry == o.entry, c)
                #expect(guess == o.guess, c)
            case .pick(let pick):
                #expect(o.kind == "pick", c)
                #expect(pick.guess == o.guess, c)
                #expect(pick.suggested.map(\.id) == o.suggested, c)
                #expect(pick.newFirst == o.newFirst, c)
            }
        }
    }

    /// A store holding this list and today's results, saved somewhere of its own.
    static func store(games: [Game], results: [String: String] = [:], stale: [String] = []) throws -> Store {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        defaults.set(try JSONEncoder().encode(games), forKey: Store.gamesKey)
        let day = Day(date: Store.dateString(Date()), results: results, stale: stale)
        defaults.set(try JSONEncoder().encode(day), forKey: Store.dayKey)
        return Store(defaults: defaults)
    }
}

final class BundleToken {}
