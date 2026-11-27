import AVFoundation
import SwiftUI

@main
struct DailyGamesApp: App {
    @State private var store: Store

    init() {
        // Music games should play even with the ringer off, as they do in Safari.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        _store = State(initialValue: Self.makeStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }

    private static func makeStore() -> Store {
        #if DEBUG
        // UI tests start from a list of their own, kept apart from the real one.
        if let json = ProcessInfo.processInfo.environment["DAILYGAMES_TEST_GAMES"], let defaults = UserDefaults(suiteName: "ui-tests") {
            defaults.removePersistentDomain(forName: "ui-tests")
            defaults.set(Data(json.utf8), forKey: Store.gamesKey)
            return Store(defaults: defaults)
        }
        #endif
        return Store()
    }
}
