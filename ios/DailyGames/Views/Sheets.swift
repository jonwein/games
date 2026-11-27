import SwiftUI

/// Asks which game a result is from: a new one (name filled in with our guess) or one already listed, with the
/// likeliest answer first.
struct PickGameSheet: View {
    let pick: Pick
    let games: [Game]
    let onChoose: (Game) -> Void
    /// Add the result as a new game with this name.
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(pick: Pick, games: [Game], onChoose: @escaping (Game) -> Void, onAdd: @escaping (String) -> Void) {
        self.pick = pick
        self.games = games
        self.onChoose = onChoose
        self.onAdd = onAdd
        _name = State(initialValue: pick.name)
    }

    private var ordered: [Game] {
        pick.suggested + games.filter { g in !pick.suggested.contains { $0.id == g.id } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(pick.text)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if pick.newFirst {
                    newGame
                    yourGames
                } else {
                    yourGames
                    newGame
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .navigationTitle("Which game is this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var newGame: some View {
        Section("New game") {
            HStack(spacing: 10) {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(add)
                if pick.newFirst {
                    Button("Add", action: add).buttonStyle(.borderedProminent)
                } else {
                    Button("Add", action: add).buttonStyle(.bordered)
                }
            }
        }
        .listRowBackground(Color.surface)
    }

    @ViewBuilder
    private var yourGames: some View {
        if !games.isEmpty {
            Section("Your games") {
                ForEach(ordered) { game in
                    let likely = !pick.newFirst && pick.suggested.contains { $0.id == game.id }
                    Button { onChoose(game) } label: {
                        HStack {
                            Text(game.name)
                                .fontWeight(likely ? .semibold : .regular)
                                .foregroundStyle(likely ? Color.accentColor : Color.ink)
                            Spacer()
                            if likely {
                                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.surface)
        }
    }

    private func add() {
        if JS.trim(name).isEmpty {
            nameFocused = true
        } else {
            onAdd(name)
        }
    }
}

/// Change a listed game's name or link.
struct EditGameSheet: View {
    let game: Game
    /// Returns what's wrong, or nil once it's saved.
    let onSave: (_ name: String, _ link: String) -> EditError?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var link: String
    @State private var error: EditError?
    @FocusState private var focus: EditError.Field?

    init(game: Game, onSave: @escaping (String, String) -> EditError?) {
        self.game = game
        self.onSave = onSave
        _name = State(initialValue: game.name)
        _link = State(initialValue: Matching.isSearch(game.url) ? "" : game.url)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focus, equals: .name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { focus = .link }
                } header: {
                    Text("Name")
                } footer: {
                    errorText(for: .name)
                }
                Section {
                    TextField("None · Play searches for it", text: $link)
                        .focused($focus, equals: .link)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                } header: {
                    Text("Link")
                } footer: {
                    errorText(for: .link)
                }
            }
            .listRowBackground(Color.surface)
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .navigationTitle("Edit Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
            .onChange(of: name) { error = nil }
            .onChange(of: link) { error = nil }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func errorText(for field: EditError.Field) -> some View {
        if let error, error.field == field {
            Text(error.message).foregroundStyle(Color.danger)
        }
    }

    private func save() {
        if let problem = onSave(name, link) {
            error = problem
            focus = problem.field
        } else {
            dismiss()
        }
    }
}

/// A short message at the bottom of the screen, sometimes with a button.
struct ToastView: View {
    let toast: Toast
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.subheadline)
                .multilineTextAlignment(toast.newGame == nil ? .center : .leading)
            if toast.newGame != nil {
                Button("Change", action: onChange)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.page.opacity(0.22), in: .rect(cornerRadius: 8))
            }
        }
        .foregroundStyle(Color.page)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.ink, in: .rect(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
