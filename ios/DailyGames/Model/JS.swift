import Foundation

/// The bits of JavaScript's string, regex and URL behavior that the matching logic relies on. That logic was
/// written for the web version (index.html), and porting it on top of these keeps both versions reading a
/// result the same way. ParityTests checks this against the web version's own answers.
enum JS {
    /// What `\s` matches in a JavaScript regex, for use inside a character class. ICU's `\s` is a slightly
    /// different set.
    static let spaceChars = #"\t\n\u000B\f\r    -     　﻿"#
    static let space = "[\(spaceChars)]"
    static let nonSpace = "[^\(spaceChars)]"
    /// `\w` is ASCII-only in JavaScript but covers all letters in ICU. The same goes for `\d` and `\b`.
    static let word = "[A-Za-z0-9_]"
    /// `\b` in front of a word character.
    static let wordStart = "(?<![A-Za-z0-9_])"
    /// `.`: anything but a line terminator. ICU's `.` also leaves out U+0085.
    static let dot = #"[^\n\r  ]"#

    private static let whitespace: CharacterSet = {
        var set = CharacterSet(charactersIn: "\t\n\u{0B}\u{0C}\r \u{A0}\u{1680}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
        set.insert(charactersIn: Unicode.Scalar(0x2000)!...Unicode.Scalar(0x200A)!)
        return set
    }()

    /// `String.prototype.trim`
    static func trim(_ s: String) -> String { s.trimmingCharacters(in: whitespace) }

    /// `String.prototype.split` with a plain separator. Unlike Swift's `split`, this splits a "\r\n" on its "\n".
    static func split(_ s: String, _ separator: String) -> [String] { s.components(separatedBy: separator) }

    /// `String.prototype.length`, which counts UTF-16 code units.
    static func length(_ s: String) -> Int { s.utf16.count }

    private static let uriUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    /// `encodeURIComponent`
    static func encodeURIComponent(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: uriUnreserved) ?? s }
}

/// A compiled regular expression with JavaScript-style helpers. Patterns are ICU syntax, so a port has to swap
/// in `JS.space`, `JS.word` and friends where JavaScript's meaning differs, and use `\z` for `$` (ICU's `$`
/// also matches just before a final line break).
struct Pattern {
    private let regex: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false, multiline: Bool = false) {
        var options: NSRegularExpression.Options = []
        if ignoreCase { options.insert(.caseInsensitive) }
        if multiline { options.insert(.anchorsMatchLines) }
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            fatalError("Bad pattern \(pattern): \(error)")
        }
    }

    private func all(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    private func groups(_ m: NSTextCheckingResult, in s: String) -> [String?] {
        let ns = s as NSString
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    /// `RegExp.prototype.test`
    func test(_ s: String) -> Bool { regex.firstMatch(in: s, range: all(s)) != nil }

    /// `String.prototype.match` without the g flag: the first match and its groups, nil for a group that took
    /// no part.
    func match(_ s: String) -> [String?]? { regex.firstMatch(in: s, range: all(s)).map { groups($0, in: s) } }

    /// `String.prototype.matchAll`
    func matchAll(_ s: String) -> [[String?]] { regex.matches(in: s, range: all(s)).map { groups($0, in: s) } }

    /// `String.prototype.replace` with the g flag and a plain replacement.
    func replaceAll(_ s: String, with replacement: String) -> String {
        regex.stringByReplacingMatches(in: s, range: all(s), withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    /// `String.prototype.replace` with the g flag and a function of the matched text.
    func replaceAll(_ s: String, _ transform: (String) -> String) -> String {
        let result = NSMutableString(string: s)
        for m in regex.matches(in: s, range: all(s)).reversed() {
            result.replaceCharacters(in: m.range, with: transform((s as NSString).substring(with: m.range)))
        }
        return result as String
    }

    /// `String.prototype.split` with a regex that never matches the empty string.
    func split(_ s: String) -> [String] {
        let ns = s as NSString
        var pieces: [String] = []
        var start = 0
        for m in regex.matches(in: s, range: all(s)) {
            pieces.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
            start = m.range.location + m.range.length
        }
        pieces.append(ns.substring(from: start))
        return pieces
    }
}

/// A link read the way JavaScript's `URL` reads it: lower-case scheme and host, "/" for an empty path, and no
/// default port.
struct WebLink {
    private var parts: URLComponents

    init?(_ string: String) {
        guard let url = URL(string: string),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased()
        else { return nil }
        parts.scheme = scheme
        if scheme == "http" || scheme == "https" {
            guard let host = parts.host, !host.isEmpty else { return nil }
            parts.host = host.lowercased()
            if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
            if parts.percentEncodedPath.isEmpty { parts.percentEncodedPath = "/" }
        }
        self.parts = parts
    }

    var hostname: String { parts.host ?? "" }

    /// The host with its port, if it has one.
    var host: String { hostname + (parts.port.map { ":\($0)" } ?? "") }

    /// The host without "www.", to compare sites.
    var site: String { (hostname.hasPrefix("www.") ? String(hostname.dropFirst(4)) : hostname).lowercased() }

    var pathname: String {
        get { parts.percentEncodedPath }
        set { parts.percentEncodedPath = newValue.isEmpty ? "/" : newValue }
    }

    mutating func removeQueryAndFragment() {
        parts.percentEncodedQuery = nil
        parts.percentEncodedFragment = nil
    }

    var href: String { parts.string ?? "" }
    var url: URL? { parts.url }
}
