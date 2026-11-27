import Foundation
import Testing
@testable import DailyGames

@MainActor
struct StoreTests {
    let spotle = "Spotle #800🎧\n\n⬜⬜⬜🟩\n\nspotle.io"
    let perceptle = "Perceptle #42 - A (87)\nhttps://perceptle.com"
    let zip = "Zip #120 | 0:23 🏁\nWith no backtracks 🟢\nlnkd.in/zip."

    private func freshStore(clock: @escaping () -> Date = Date.init) throws -> (Store, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
        return (Store(defaults: defaults, clock: clock), defaults)
    }

    private func toast(_ feedback: Feedback) -> Toast? {
        if case .toast(let t) = feedback { return t }
        return nil
    }

    @Test func startsWithTheStarterGames() throws {
        let (store, _) = try freshStore()
        #expect(store.games == Game.starters)
        #expect(store.doneCount == 0)
        #expect(store.suggestions.isEmpty)
    }

    @Test func addsAndUpdatesResults() throws {
        let (store, _) = try freshStore()
        #expect(toast(store.handle(spotle))?.message == "Added Spotle · 5 to go")
        #expect(toast(store.handle("Spotle #801🎧\n⬜🟩"))?.message == "Updated Spotle · 5 to go")
        #expect(store.doneCount == 1)
    }

    @Test func saysAllDone() throws {
        let (store, _) = try freshStore()
        for game in store.games { store.add(game, "\(game.name) #1 ✅") }
        #expect(store.allDone)
        let last = store.games[0]
        #expect(store.add(last, "\(last.name) #2 ✅").message == "Updated \(last.name) · all done!")
    }

    @Test func messageFollowsListOrderWithoutLinks() throws {
        let (store, _) = try freshStore()
        _ = store.handle(spotle)
        _ = store.handle(perceptle)
        #expect(store.message == "Perceptle #42 - A (87)\n\nSpotle #800🎧\n\n⬜⬜⬜🟩")
    }

    @Test func newGameCanBeChangedBack() throws {
        let (store, _) = try freshStore()
        let added = try #require(toast(store.handle(zip)))
        #expect(added.message == "Added Zip as a new game")
        #expect(store.games.last?.name == "Zip")
        #expect(store.games.last?.url == "https://lnkd.in/zip")

        let pick = store.undo(try #require(added.newGame))
        #expect(!store.games.contains { $0.name == "Zip" })
        #expect(store.doneCount == 0)
        #expect(pick.name == "Zip")
        #expect(pick.newFirst)
    }

    @Test func pickingAGameTeachesItTheResultsName() throws {
        let (store, _) = try freshStore()
        // As after tapping Change on "Added Krill as a new game".
        guard case .addNew(_, let text, let guess) = store.decide("Krill #3 🦐 4/6") else { Issue.record("expected a new game"); return }
        let pick = Pick(text: text, guess: guess, suggested: [], newFirst: true)
        let krillion = try #require(store.games.first { $0.id == "krillion" })
        let toast = store.choose(krillion, for: pick)
        #expect(toast.message == "Added Krillion · 5 to go")
        #expect(store.games.first { $0.id == "krillion" }?.alias == "Krill")

        // The next one goes straight in.
        _ = store.handle("Krill #4 🦐 3/6")
        #expect(store.result(for: krillion) == "Krill #4 🦐 3/6")
    }

    @Test func namingANewGameFromThePicker() throws {
        let (store, _) = try freshStore()
        let pick = Pick(text: "Krill #3 🦐 4/6", guess: GameEntry(name: "Krill", url: Matching.searchURL(for: "Krill")), suggested: [], newFirst: true)
        #expect(store.addNamed("   ", for: pick) == nil)

        // A listed name picks that game.
        #expect(store.addNamed("krillion", for: pick)?.message == "Added Krillion · 5 to go")

        // A new name the result doesn't use remembers the one it does.
        let other = Pick(text: "Blip #9 ✅", guess: GameEntry(name: "Blip", url: Matching.searchURL(for: "Blip")), suggested: [], newFirst: true)
        #expect(store.addNamed("Blip Blop", for: other)?.message == "Added Blip Blop as a new game")
        let blop = try #require(store.games.last)
        #expect(blop.alias == "Blip")
        #expect(blop.url == Matching.searchURL(for: "Blip Blop"))
    }

    @Test func editingAGame() throws {
        let (store, _) = try freshStore()
        #expect(store.updateGame("krillion", name: "  ", link: "") == EditError(field: .name, message: "Give it a name."))
        #expect(store.updateGame("krillion", name: "spotle", link: "") == EditError(field: .name, message: "spotle is already on your list."))
        #expect(store.updateGame("krillion", name: "Krill", link: "not a link") == EditError(field: .link, message: "That link doesn't look right."))

        // Renaming keeps answering to the old name, and an empty link searches.
        #expect(store.updateGame("krillion", name: "  Krill   Game ", link: "") == nil)
        var g = try #require(store.games.first { $0.id == "krillion" })
        #expect(g.name == "Krill Game")
        #expect(g.alias == "Krillion")
        #expect(g.url == Matching.searchURL(for: "Krill Game"))
        if case .add(let added, _) = store.decide("Krillion #95 🦐 4/6") { #expect(added.id == "krillion") } else { Issue.record("expected an add") }

        // Renaming back drops the alias.
        #expect(store.updateGame("krillion", name: "Krillion", link: "krillion.io") == nil)
        g = try #require(store.games.first { $0.id == "krillion" })
        #expect(g.alias == nil)
        #expect(g.url == "https://krillion.io/")
    }

    @Test func addingAGameByLink() throws {
        let (store, _) = try freshStore()
        #expect(store.addGame(link: "nope", name: "") == (false, "That link doesn't look right."))
        #expect(store.addGame(link: "spotle.io", name: "Spotle") == (false, "Spotle is already on your list."))
        #expect(store.addGame(link: "lessgames.com/songless", name: "") == (false, "Songless is already on your list."))
        #expect(store.addGame(link: "globle-game.com/game", name: "") == (true, "Added Globle Game"))
        #expect(store.games.last?.url == "https://globle-game.com/game")
    }

    @Test func removedStartersCanBeAddedBack() throws {
        let (store, _) = try freshStore()
        store.deleteGames(at: [0])
        #expect(store.suggestions.map(\.id) == ["perceptle"])
        store.addSuggestion(store.suggestions[0])
        #expect(store.suggestions.isEmpty)
        #expect(store.games.last?.id == "perceptle")
    }

    @Test func reordering() throws {
        let (store, _) = try freshStore()
        store.moveGames(from: [0], to: 3)
        #expect(store.games.map(\.id).prefix(3) == ["dailytens", "songless", "perceptle"])
    }

    @Test func aNewDayStartsFresh() throws {
        final class Clock { var now = Date() }
        let clock = Clock()
        let (store, defaults) = try freshStore { clock.now }
        _ = store.handle(spotle)
        #expect(store.doneCount == 1)

        clock.now = clock.now.addingTimeInterval(36 * 3600)
        store.checkDay()
        #expect(store.doneCount == 0)
        #expect(toast(store.handle(spotle))?.message == "That's an old result. Tap Share in the game first.")

        // And it's saved that way.
        let reopened = Store(defaults: defaults, clock: { clock.now })
        #expect(reopened.day == store.day)
    }

    @Test func savesBetweenLaunches() throws {
        let (store, defaults) = try freshStore()
        _ = store.handle(spotle)
        store.moveGames(from: [3], to: 0)
        _ = store.addGame(link: "wafflegame.net", name: "")

        let reopened = Store(defaults: defaults)
        #expect(reopened.games == store.games)
        #expect(reopened.day == store.day)
    }

    @Test func clearingAResult() throws {
        let (store, _) = try freshStore()
        _ = store.handle(spotle)
        store.clearResult(try #require(store.games.first { $0.id == "spotle" }))
        #expect(store.doneCount == 0)
    }
}
