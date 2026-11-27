import Combine
import SwiftUI
import UIKit

/// Today's games: play each one, and its result comes back here. Then send them all in one message.
struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var editMode = EditMode.inactive
    @State private var playing: Game?
    /// A result caught while a game was open, handled once its browser has closed.
    @State private var caught: String?
    @State private var pick: Pick?
    @State private var editingGame: Game?
    @State private var toast: Toast?
    @State private var nudges = 0
    @State private var successes = 0
    @State private var newLink = ""
    @State private var newName = ""

    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        NavigationStack {
            List {
                gamesSection
                if isEditing {
                    addSection
                    suggestionsSection
                }
            }
            .listStyle(.insetGrouped)
            .listRowSpacing(10)
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .environment(\.editMode, $editMode)
            .navigationTitle("Daily Games")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = isEditing ? .inactive : .active }
                    }
                    .fontWeight(isEditing ? .semibold : .regular)
                }
            }
            // Above the bottom bar, since the bar is inset below it.
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(toast: toast) { change(toast) }
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isEditing { bottomBar }
            }
        }
        .tint(.accentColor)
        .sensoryFeedback(.success, trigger: successes)
        .fullScreenCover(item: $playing, onDismiss: browserClosed) { game in
            GameBrowser(game: game) { caught = $0 }
        }
        .sheet(item: $pick) { pick in
            PickGameSheet(pick: pick, games: store.games) { game in
                self.pick = nil
                show(store.choose(game, for: pick))
            } onAdd: { name in
                if let result = store.addNamed(name, for: pick) {
                    self.pick = nil
                    show(result)
                }
            }
        }
        .sheet(item: $editingGame) { game in
            EditGameSheet(game: game) { name, link in
                store.updateGame(game.id, name: name, link: link)
            }
        }
        .task(id: toast?.id) {
            guard let shown = toast else { return }
            try? await Task.sleep(for: .seconds(shown.newGame == nil ? 2.6 : 6))
            if toast?.id == shown.id { withAnimation { toast = nil } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.checkDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            store.checkDay()
        }
        #if DEBUG
        .task {
            // Tests can open a game, or Edit, on launch.
            let env = ProcessInfo.processInfo.environment
            if let id = env["DAILYGAMES_TEST_OPEN"], let game = store.games.first(where: { $0.id == id }) {
                play(game)
            }
            if env["DAILYGAMES_TEST_EDIT"] != nil { editMode = .active }
        }
        #endif
    }

    // MARK: The list

    private var gamesSection: some View {
        Section {
            ForEach(store.games) { game in
                Group {
                    if isEditing { editRow(game) } else { playRow(game) }
                }
                .listRowBackground(Color.surface)
            }
            .onMove(perform: isEditing ? { store.moveGames(from: $0, to: $1) } : nil)
            .onDelete(perform: isEditing ? { store.deleteGames(at: $0) } : nil)

            if store.games.isEmpty && !isEditing {
                Text("No games yet. Paste a result to add its game, or tap Edit.")
                    .foregroundStyle(Color.muted)
                    .listRowBackground(Color.surface)
            }
        } header: {
            Text(store.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(Color.muted)
                .textCase(nil)
        } footer: {
            Text(isEditing
                ? "Tap a game to change its name or link. Results go into the message in this order. Your list is saved on this phone only."
                : "Tap a game to play it. When you tap Share at the end, your result lands here. Played it somewhere else? Copy the result and tap Paste.")
                .foregroundStyle(Color.muted)
                .padding(.top, 8)
        }
    }

    private func playRow(_ game: Game) -> some View {
        let result = store.result(for: game)
        return Button { play(game) } label: {
            HStack(spacing: 12) {
                CheckCircle(done: result != nil)
                VStack(alignment: .leading, spacing: 1) {
                    Text(game.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.ink)
                    Text(result.map { JS.split($0, "\n")[0] } ?? "Not played yet")
                        .font(.subheadline)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if result == nil {
                    Text("Play ›")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .swipeActions(edge: .trailing) {
            if result != nil {
                Button("Clear", role: .destructive) { withAnimation { store.clearResult(game) } }
            }
        }
        .contextMenu {
            Button { play(game) } label: { Label("Play", systemImage: "play") }
            if let result {
                Button { UIPasteboard.general.string = result } label: { Label("Copy Result", systemImage: "doc.on.doc") }
                Button(role: .destructive) { withAnimation { store.clearResult(game) } } label: {
                    Label("Clear Result", systemImage: "xmark.circle")
                }
            }
        }
        .accessibilityHint(result == nil ? "Opens the game" : "Played. Swipe to clear the result.")
    }

    private func editRow(_ game: Game) -> some View {
        Button { editingGame = game } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(game.name)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.ink)
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(Color.muted)
                }
                Text(linkLabel(game))
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .accessibilityLabel("Edit \(game.name)")
    }

    private func linkLabel(_ game: Game) -> String {
        if Matching.isSearch(game.url) { return "No link · Play searches for it" }
        guard let host = WebLink(game.url)?.host else { return game.url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var addSection: some View {
        Section {
            TextField("Link, like nytimes.com/games/wordle", text: $newLink)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
            TextField("Name (optional)", text: $newName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(addGame)
            Button("Add Game", action: addGame)
                .fontWeight(.semibold)
                .disabled(JS.trim(newLink).isEmpty)
        } header: {
            Text("Add a game")
        }
        .listRowBackground(Color.surface)
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        let suggestions = store.suggestions
        if !suggestions.isEmpty {
            Section("Starter games") {
                ForEach(suggestions) { game in
                    Button { withAnimation { store.addSuggestion(game) } } label: {
                        Label(game.name, systemImage: "plus.circle.fill")
                    }
                }
            }
            .listRowBackground(Color.surface)
        }
    }

    // MARK: The bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            PasteControl(prominent: !store.allDone) { text in
                apply(store.handle(text))
            }
            .id(store.allDone)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
            .phaseAnimator([1.0, 1.04, 1.0, 1.04, 1.0], trigger: nudges) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in .easeInOut(duration: 0.22) }
            .accessibilityLabel("Paste result")

            ShareLink(item: store.message) {
                Text(store.allDone ? "Send all" : "Send \(store.doneCount)/\(store.games.count)")
            }
            .buttonStyle(BarButtonStyle(prominent: store.allDone))
            .disabled(store.doneCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.bar)
                .overlay(alignment: .top) { Divider() }
                .ignoresSafeArea()
        }
    }

    // MARK: Actions

    private func play(_ game: Game) {
        store.lastOpened = game.id
        caught = nil
        playing = game
    }

    /// Back from a game: add the result it shared, or nudge Paste if there wasn't one.
    private func browserClosed() {
        store.checkDay()
        if let text = caught {
            caught = nil
            apply(store.handle(text))
        } else if let id = store.lastOpened, store.day.results[id] == nil {
            nudges += 1
        }
    }

    private func apply(_ feedback: Feedback) {
        switch feedback {
        case .toast(let toast): show(toast)
        case .pick(let pick): self.pick = pick
        }
    }

    private func show(_ toast: Toast) {
        withAnimation(.snappy) { self.toast = toast }
        if toast.success { successes += 1 }
    }

    private func change(_ toast: Toast) {
        guard let newGame = toast.newGame else { return }
        withAnimation { self.toast = nil }
        pick = store.undo(newGame)
    }

    private func addGame() {
        let result = store.addGame(link: newLink, name: newName)
        if result.added {
            newLink = ""
            newName = ""
        }
        show(Toast(message: result.message))
    }
}

#Preview {
    ContentView().environment(Store(defaults: UserDefaults(suiteName: "preview")!))
}
