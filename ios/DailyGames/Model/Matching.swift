import Foundation

/// Working out which game a result is from. This is a port of the matching in the web version (index.html),
/// function for function. Keep the two in step: after changing the web version, run
/// `node ios/Tools/make_fixtures.mjs` and ParityTests shows where the app now reads a result differently.
enum Matching {
    // MARK: Names

    private static var matchers: [String: Pattern] = [:]
    private static let whitespaceRuns = Pattern(JS.space + "+")

    /// Share texts almost always include the game's name ("DailyTens #120", "Spotle.io #800"), so match on that
    /// as a whole word, ignoring case and spaces between words. "Wordle" doesn't match "Wordless", but a number
    /// may follow ("Waffle" matches "#waffle800").
    static func matcher(_ name: String) -> Pattern {
        if let cached = matchers[name] { return cached }
        let words = whitespaceRuns.split(JS.trim(name)).map(NSRegularExpression.escapedPattern(for:))
        let pattern = Pattern(#"(?:^|[^\p{L}\p{N}])"# + words.joined(separator: JS.space + "*") + #"(?!\p{L})"#, ignoreCase: true)
        matchers[name] = pattern
        return pattern
    }

    /// Whether the text names the game, by its name or the name its results use.
    static func mentions(_ game: Game, _ text: String) -> Bool {
        game.names.contains { matcher($0).test(text) }
    }

    /// Listed games named in the text. A name inside a longer matching name doesn't count: "Daily Tens #1" is
    /// Daily Tens, not a game called "Tens".
    static func mentioned(_ text: String, in games: [Game]) -> [Game] {
        let hits = games.filter { mentions($0, text) }
        return hits.filter { g in
            !hits.contains { h in JS.length(h.name) > JS.length(g.name) && matcher(g.name).test(h.name) }
        }
    }

    /// The matching game, or nil when none or several match.
    static func detect(_ text: String, in games: [Game]) -> Game? {
        let hits = mentioned(text, in: games)
        return hits.count == 1 ? hits[0] : nil
    }

    /// A link in a result: "https://…" or "www.…".
    static let link = Pattern(JS.wordStart + #"(?:https?://|www\.)"# + JS.nonSpace + "+", ignoreCase: true)
    private static let letter = Pattern(#"\p{L}"#)

    /// The first line with words in it, minus links. That's where a result names its game.
    static func headLine(_ text: String) -> String {
        JS.split(text, "\n").map { link.replaceAll($0, with: "") }.first { letter.test($0) } ?? ""
    }

    // MARK: Links

    static let searchPrefix = "https://www.google.com/search?q="
    static func isSearch(_ href: String) -> Bool { href.hasPrefix(searchPrefix) }
    static func searchURL(for name: String) -> String { searchPrefix + JS.encodeURIComponent(name + " game") }

    private static let fullLink = Pattern(JS.wordStart + #"https?://[^"# + JS.spaceChars + #"<>"]+"#, ignoreCase: true)
    private static let bareLink = Pattern(
        #"(?:^|["# + JS.spaceChars + #"(])((?:[a-z0-9-]+\.)+[a-z]{2,6}(?:/[^"# + JS.spaceChars + #"<>"]*)?)"#,
        ignoreCase: true, multiline: true
    )
    private static let trailingPunctuation = Pattern(#"[.,;:!?)\]'"’”]+\z"#)
    private static let httpScheme = Pattern("^https?:", ignoreCase: true)
    private static let digit = Pattern("[0-9]")

    /// The first link in a result ("https://…", or bare like "lnkd.in/zip." and "Spotle.io"), cut back to the
    /// game's own page: no query, and nothing from a segment with a number on, since that's one day's puzzle
    /// ("immaculategrid.com/grid-300" → "https://immaculategrid.com/").
    static func findLink(_ text: String) -> String? {
        guard let m = fullLink.match(text) ?? bareLink.match(text), let found = (m.count > 1 ? m[1] : nil) ?? m[0] else { return nil }
        let raw = trailingPunctuation.replaceAll(found, with: "")
        guard var u = WebLink(httpScheme.test(raw) ? raw : "https://" + raw) else { return nil }
        let segments = JS.split(u.pathname, "/")
        let cut = segments.firstIndex { digit.test($0) }
        u.pathname = (cut.map { Array(segments[..<$0]) } ?? segments).joined(separator: "/")
        u.removeQueryAndFragment()
        return u.href
    }

    private static let indexPage = Pattern(#"/(?:index\.[A-Za-z0-9_]+)?\z"#, ignoreCase: true)

    /// The one listed game whose page this link is on or under ("lessgames.com/songless/12" → Songless).
    static func listedAt(_ href: String?, in games: [Game]) -> Game? {
        guard let href, !isSearch(href), let u = WebLink(href) else { return nil }
        let path = u.pathname.lowercased()
        let hits = games.filter { g in
            guard !isSearch(g.url), let v = WebLink(g.url), v.site == u.site else { return false }
            let base = indexPage.replaceAll(v.pathname, with: "").lowercased()
            return path == base || path.hasPrefix(base + "/")
        }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Where to play games whose results don't link back to them, or link only to a results page on the same site.
    static let knownLinks: [String: String] = [
        "wordle": "https://www.nytimes.com/games/wordle/index.html",
        "connections": "https://www.nytimes.com/games/connections",
        "strands": "https://www.nytimes.com/games/strands",
        "crossword": "https://www.nytimes.com/crosswords/game/daily",
        "daily crossword": "https://www.nytimes.com/crosswords/game/daily",
        "nyt crossword": "https://www.nytimes.com/crosswords/game/daily",
        "mini": "https://www.nytimes.com/crosswords/game/mini",
        "mini crossword": "https://www.nytimes.com/crosswords/game/mini",
        "pips": "https://www.nytimes.com/games/pips",
    ]

    static func urlFor(_ name: String, link: String?) -> String {
        let known = knownLinks[name.lowercased()]
        if let known, link == nil || WebLink(known)?.site == link.flatMap(WebLink.init)?.site { return known }
        return link ?? known ?? searchURL(for: name)
    }

    // MARK: Guessing a new game

    /// Words that start a first line without naming a game: dates ("🌎 Mar 5, 2024"), "Puzzle #12", "Today's".
    private static let filler = Pattern(
        #"^(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?|today(?:['’]?s)?|daily|day|puzzle|games?|results?|score|streak|i|the|my)\z"#,
        ignoreCase: true
    )
    static func isFiller(_ name: String) -> Bool { whitespaceRuns.split(name).allSatisfy(filler.test) }

    private static let title = Pattern(#"^[^\p{L}\p{N}]*(\p{L}[\p{L}\p{N}'’]*(?:[ \t]+\p{Lu}[\p{L}\p{N}'’]*)*)("# + JS.dot + #"*)\z"#)
    private static let sentenceGoesOn = Pattern(#"^[ \t]+\p{L}"#)
    private static let spacesOrTabs = Pattern("[ \t]+")
    private static let leadIn = Pattern(#"^(?:the|my|today(?:['’]?s)?)\z"#, ignoreCase: true)

    /// The title a line starts with: "Wordle 1,234 4/6" → "Wordle", "#Worldle #800" → "Worldle", "Daily Quordle
    /// 800" → "Daily Quordle", "Spotle.io #800" → "Spotle". A line that reads as a sentence ("I played
    /// contexto.me…") has none.
    static func titleOf(_ line: String) -> String? {
        guard let m = title.match(line), let head = m[1], !sentenceGoesOn.test(m[2] ?? "") else { return nil }
        var words = spacesOrTabs.split(head)
        while words.count > 1, leadIn.test(words[0]) { words.removeFirst() }
        return words.count <= 4 ? words.joined(separator: " ") : nil
    }

    private static let trailingDigits = Pattern("[0-9]+\\z")
    private static let wordInitial = Pattern("(?:^|" + JS.space + #")\p{L}"#)

    /// "waffle800" → "Waffle". Names in all lower case get capitals; others keep theirs ("TimeGuessr").
    static func tidyName(_ s: String) -> String {
        let name = JS.trim(trailingDigits.replaceAll(s, with: ""))
        return name == name.lowercased() ? wordInitial.replaceAll(name) { $0.uppercased() } : name
    }

    private static let hashtag = Pattern(#"#(\p{L}[\p{L}\p{N}]*)"#)

    /// A name and link for a result from a game that isn't listed. The name has to be in the result so the next
    /// one matches it: the title on its first line, else a hashtag, else the site it links to.
    static func guessGame(_ text: String) -> GameEntry? {
        let link = findLink(text)
        let tags = hashtag.matchAll(text).compactMap { $0[1] }
        let fromLink = link.map(nameFromUrl) ?? ""
        let candidates: [String?] = [titleOf(headLine(text))] + tags + [fromLink, JS.split(fromLink, " ")[0]]
        for case let raw? in candidates where !raw.isEmpty {
            let name = tidyName(raw)
            if !name.isEmpty, JS.length(name) <= 30, !isFiller(name), matcher(name).test(text) {
                return GameEntry(name: name, url: urlFor(name, link: link))
            }
        }
        return nil
    }

    private static let numberOrPictograph = Pattern(#"\p{N}|\p{Extended_Pictographic}"#)

    /// Results have a number or an emoji outside their links; most other copied text doesn't.
    static func looksLikeResult(_ text: String) -> Bool {
        numberOrPictograph.test(link.replaceAll(text, with: ""))
    }

    // MARK: Adding games by link

    private static let httpSchemeAndSlashes = Pattern("^https?://", ignoreCase: true)

    /// A typed link as a full one ("nytimes.com/games/wordle" → "https://nytimes.com/games/wordle"), or nil when
    /// it doesn't look like one.
    static func normalizeUrl(_ raw: String) -> String? {
        var s = JS.trim(raw)
        if !httpSchemeAndSlashes.test(s) { s = "https://" + s }
        guard let u = WebLink(s), u.hostname.contains(".") else { return nil }
        return u.href
    }

    private static let genericSegment = Pattern(#"^(?:index(?:\.[A-Za-z0-9_]+)?|games?|play|daily|today|puzzles?|app|en|[0-9]+)\z"#, ignoreCase: true)
    private static let fileExtension = Pattern(#"\.[A-Za-z0-9_]+\z"#)
    private static let dashes = Pattern("[-_]+")
    private static let asciiWordInitial = Pattern(JS.wordStart + JS.word)

    /// "lessgames.com/songless" → "Songless", "chainle.io" → "Chainle", "globle-game.com/game" → "Globle Game"
    static func nameFromUrl(_ href: String) -> String {
        guard let u = WebLink(href) else { return "" }
        let segment = JS.split(u.pathname, "/").last { !$0.isEmpty && !genericSegment.test($0) }
        let host = u.hostname.hasPrefix("www.") ? String(u.hostname.dropFirst(4)) : u.hostname
        let base = fileExtension.replaceAll(segment ?? JS.split(host, ".")[0], with: "")
        return JS.trim(asciiWordInitial.replaceAll(dashes.replaceAll(base, with: " ")) { $0.uppercased() })
    }

    // MARK: The message

    private static let bareDomainLine = Pattern(#"^(?:[A-Za-z0-9_-]+\.)+[a-z]{2,}(?:/"# + JS.nonSpace + #"*)?\z"#, ignoreCase: true)
    private static let trailingSpace = Pattern("[ \t]+\\z")
    private static let extraBlankLines = Pattern("\n{3,}")

    /// Drop links from a result, along with lines left as just a label ("Play Today's Game: https://…" → gone)
    /// and lines that are only a bare link ("lnkd.in/zip"). A domain inside a line ("Spotle.io #800") stays.
    static func stripLinks(_ text: String) -> String {
        var lines: [String] = []
        for line in JS.split(text, "\n") {
            if bareDomainLine.test(JS.trim(line)) { continue }
            let rest = trailingSpace.replaceAll(link.replaceAll(line, with: ""), with: "")
            if rest != trailingSpace.replaceAll(line, with: ""), JS.trim(rest).isEmpty || rest.hasSuffix(":") { continue }
            lines.append(rest)
        }
        let cleaned = JS.trim(extraBlankLines.replaceAll(lines.joined(separator: "\n"), with: "\n\n"))
        return cleaned.isEmpty ? text : cleaned
    }
}
