import Foundation

/// Turns an agent's last answer into one readable line. Recaps come out of
/// raw model output — markdown headers, bullets, code fences, links — and a
/// hover card has room for two short lines, so everything that isn't prose
/// is stripped before any truncation happens.
enum RecapText {
    /// Markdown → plain prose, single line. Fenced code blocks are dropped
    /// entirely (code is never a good recap); headings, list markers,
    /// blockquotes, emphasis, and links reduce to their text.
    static func plain(_ raw: String) -> String {
        var lines: [String] = []
        var inFence = false
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if line.isEmpty { continue }
            // Horizontal rules and bare table separators are pure noise.
            if line.allSatisfy({ "-*=_| :".contains($0) }) { continue }
            lines.append(stripInline(stripLinePrefix(line)))
        }
        return lines.joined(separator: " ")
            .replacingOccurrences(
                of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Leading heading/list/quote markers.
    private static func stripLinePrefix(_ line: String) -> String {
        var s = Substring(line)
        while s.first == ">" { s = s.dropFirst().drimmed }
        while s.first == "#" { s = s.dropFirst() }
        if s.first == " " { s = s.drimmed }
        // Unordered list marker: "- ", "* ", "+ ".
        if let first = s.first, "-*+".contains(first), s.dropFirst().first == " " {
            s = s.dropFirst(2).drimmed
        }
        // Ordered list marker: "12. " / "12) ".
        let digits = s.prefix(while: \.isNumber)
        if !digits.isEmpty, digits.count <= 3 {
            let rest = s.dropFirst(digits.count)
            if rest.first == "." || rest.first == ")", rest.dropFirst().first == " " {
                s = rest.dropFirst(2).drimmed
            }
        }
        return String(s)
    }

    /// Inline markdown: links/images keep their text, emphasis markers and
    /// backticks vanish. Single `*`/`_` are left alone (snake_case, globs).
    private static func stripInline(_ line: String) -> String {
        var s = line
        // ![alt](url) and [text](url) → alt/text.
        s = s.replacingOccurrences(
            of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for marker in ["**", "__", "`"] {
            s = s.replacingOccurrences(of: marker, with: "")
        }
        return s
    }

    /// Clean + cap for an adapter's `recap` field: plain prose, word-boundary
    /// prefix under `limit`. Nil when nothing readable survives.
    static func recap(_ raw: String, limit: Int = 200) -> String? {
        let text = plain(raw)
        guard !text.isEmpty else { return nil }
        return text.count > limit ? wordPrefix(text, limit: limit) + "…" : text
    }

    /// Display excerpt for the hover card: whole sentences while they fit,
    /// else a word-boundary cut. Sentence detection skips abbreviations
    /// (`e.g.`, `i.e.`, `etc.`, `vs.`) and dotted numbers (`v1. 2`).
    static func excerpt(_ text: String, limit: Int = 140) -> String? {
        let flat = plain(text)
        guard !flat.isEmpty else { return nil }
        if flat.count <= limit { return flat }

        var taken = ""
        var rest = Substring(flat)
        while let end = sentenceEnd(in: rest) {
            // The slice runs past the terminator's trailing space already.
            let candidate = taken + rest[..<end]
            if candidate.count > limit { break }
            taken = candidate
            rest = rest[end...].drimmed
        }
        let trimmed = taken.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 12 { return trimmed }
        return wordPrefix(flat, limit: limit) + "…"
    }

    /// Index just past the first genuine sentence terminator, or nil.
    private static func sentenceEnd(in text: Substring) -> Substring.Index? {
        var index = text.startIndex
        while let range = text.range(of: #"[.!?] "#, options: .regularExpression,
                                     range: index..<text.endIndex) {
            index = range.upperBound
            if text[range.lowerBound] != "." { return range.upperBound }
            let head = text[..<range.lowerBound]
            let word = head.trailingWord.lowercased()
            let bare = word.replacingOccurrences(of: ".", with: "")
            if ["eg", "ie", "etc", "vs", "cf", "approx", "no", "dr", "mr", "ms", "mrs", "st"]
                .contains(bare) { continue }
            // "v1. 2" / "3. 4" — a dot glued to digits isn't a sentence end.
            if word.last == ".", word.dropLast().last?.isNumber == true { continue }
            return range.upperBound
        }
        return nil
    }

    private static func wordPrefix(_ text: String, limit: Int) -> String {
        let head = String(text.prefix(limit))
        if let space = head.lastIndex(of: " "),
           head.distance(from: head.startIndex, to: space) >= limit / 2 {
            return String(head[..<space]).trimmingCharacters(in: .whitespaces)
        }
        return head.trimmingCharacters(in: .whitespaces)
    }
}

private extension Substring {
    /// Trim leading whitespace only (prefix stripping walks left-to-right).
    var drimmed: Substring { drop(while: { $0 == " " || $0 == "\t" }) }

    /// The run of non-whitespace characters ending the substring.
    var trailingWord: Substring {
        var start = endIndex
        while start > startIndex, !self[index(before: start)].isWhitespace {
            start = index(before: start)
        }
        return self[start...]
    }
}
