import Foundation

/// Pure parsing helpers for the JSONL session formats Hubby reads.
/// Kept free of filesystem access so tests can feed fixture data directly.
enum JSONLParsers {

    /// Derive a human title from a Claude Code session file
    /// (`~/.claude/projects/<project>/<session>.jsonl`).
    ///
    /// Preference order: a `summary` line, else the first real user message.
    /// Returns nil when neither is present (e.g. bookkeeping-only files).
    static func claudeCodeTitle(fromHead data: Data) -> String? {
        var firstUserText: String?
        for line in jsonLines(in: data) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let type = obj["type"] as? String {
                if type == "summary", let summary = obj["summary"] as? String, !summary.isEmpty {
                    return clean(summary)
                }
                if type == "user", firstUserText == nil,
                   let message = obj["message"] as? [String: Any],
                   let text = messageText(message), !text.isEmpty,
                   !text.hasPrefix("<") { // skip command/system-reminder payloads
                    firstUserText = clean(text)
                }
            }
        }
        return firstUserText
    }

    /// The last thing Claude said in a session — the hover recap. Scans a
    /// tail read backwards for the newest assistant text block (a leading
    /// partial line just fails JSON parsing and is skipped).
    static func claudeCodeRecap(fromTail data: Data) -> String? {
        for line in jsonLines(in: data).reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let text = messageText(message), !text.isEmpty else { continue }
            return clean(text, limit: 200)
        }
        return nil
    }

    /// The last agent message in a Codex rollout tail — the hover recap.
    /// Covers both stream shapes: `event_msg`/`agent_message` events and
    /// `response_item` assistant messages with `output_text` blocks.
    static func codexRecap(fromTail data: Data) -> String? {
        for line in jsonLines(in: data).reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "event_msg":
                if payload["type"] as? String == "agent_message",
                   let text = payload["message"] as? String, !text.isEmpty {
                    return clean(text, limit: 200)
                }
            case "response_item":
                if payload["type"] as? String == "message",
                   payload["role"] as? String == "assistant",
                   let blocks = payload["content"] as? [[String: Any]] {
                    for block in blocks where block["type"] as? String == "output_text" {
                        if let text = block["text"] as? String, !text.isEmpty {
                            return clean(text, limit: 200)
                        }
                    }
                }
            default:
                break
            }
        }
        return nil
    }

    /// Working directory recorded in a Claude Code session head, if any.
    static func claudeCodeCwd(fromHead data: Data) -> String? {
        for line in jsonLines(in: data) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let cwd = obj["cwd"] as? String, !cwd.isEmpty else { continue }
            return cwd
        }
        return nil
    }

    /// Parse the `session_meta` head line of a Codex rollout file
    /// (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).
    /// Returns (title, cwd); title falls back to the cwd's last component.
    static func codexMeta(fromHead data: Data) -> (title: String, cwd: String?)? {
        for line in jsonLines(in: data) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  obj["type"] as? String == "session_meta",
                  let payload = obj["payload"] as? [String: Any] else { continue }
            let cwd = payload["cwd"] as? String
            let title = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Codex session"
            return (clean(title), cwd)
        }
        return nil
    }

    // MARK: - Codex session index

    /// One line of `~/.codex/session_index.jsonl`.
    struct CodexIndexEntry {
        let id: String
        let name: String?
        let updatedAt: Date?
    }

    /// Parse `session_index.jsonl` data (typically a tail read — a leading
    /// partial line just fails JSON parsing and is skipped). Entries are
    /// append-ordered, so for duplicate ids the LAST entry wins; collapse
    /// with `Dictionary(..., uniquingKeysWith: { _, last in last })`.
    static func codexSessionIndex(from data: Data) -> [CodexIndexEntry] {
        jsonLines(in: data).compactMap { line in
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = obj["id"] as? String, !id.isEmpty else { return nil }
            let rawName = (obj["thread_name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CodexIndexEntry(
                id: id,
                name: (rawName?.isEmpty ?? true) ? nil : rawName.map { clean($0) },
                updatedAt: (obj["updated_at"] as? String).flatMap(lenientISODate))
        }
    }

    /// The index file contains garbage dates in the wild (`…:17.3NZ`,
    /// epoch-2000 sentinels), so parse leniently and reject sentinels.
    static func lenientISODate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: string) ?? plain.date(from: string) else {
            return nil
        }
        // Anything at/before 2001 is a sentinel, not a real session time.
        return date.timeIntervalSinceReferenceDate <= 0 ? nil : date
    }

    // MARK: - Helpers

    private static func jsonLines(in data: Data) -> [Data] {
        let newline = UInt8(ascii: "\n")
        let slices: [Data.SubSequence] = data.split(separator: newline)
        return slices.map { Data($0) }
    }

    /// Extract text from a Claude message `content`, which is either a plain
    /// string or an array of `{type: "text", text: ...}` blocks.
    private static func messageText(_ message: [String: Any]) -> String? {
        if let text = message["content"] as? String { return text }
        if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks where block["type"] as? String == "text" {
                if let text = block["text"] as? String { return text }
            }
        }
        return nil
    }

    static func clean(_ raw: String, limit: Int = 60) -> String {
        let oneLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count > limit ? String(oneLine.prefix(limit)) + "…" : oneLine
    }
}
