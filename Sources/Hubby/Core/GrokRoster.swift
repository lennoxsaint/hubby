import Foundation

/// Grok Bot ("Sand") stores its agent roster as JSON blobs under
/// `~/Library/Application Support/Grok Bot/sand-client-persistence/`, with
/// each filename the lowercase base32 of its key. The roster blob's key ends
/// in `roster.last-roster` and carries every agent's name, title, activity
/// timestamps, and — uniquely among agent apps — an `awaitingUserResponse`
/// marker: the agent is blocked on the human.
enum GrokRoster {
    /// RFC 4648 base32 (no padding needed; case-insensitive).
    static func base32Decode(_ input: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var lookup = [Character: UInt32]()
        for (index, char) in alphabet.enumerated() {
            lookup[char] = UInt32(index)
        }
        var bits: UInt32 = 0
        var bitCount = 0
        var out = Data()
        for char in input.uppercased() where char != "=" {
            guard let value = lookup[char] else { return nil }
            bits = (bits << 5) | value
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                out.append(UInt8((bits >> UInt32(bitCount)) & 0xFF))
            }
        }
        return out
    }

    /// Decode a blob filename (`<base32>.blob`) back to its key string.
    static func key(forBlobFilename filename: String) -> String? {
        guard filename.hasSuffix(".blob") else { return nil }
        return base32Decode(String(filename.dropLast(".blob".count)))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Parse the roster blob into threads: awaiting-user first, then recency.
    static func parse(_ data: Data, cap: Int = 8, now: Date = Date()) -> [AgentThread] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = root["value"] as? [String: Any],
              let rows = value["rows"] as? [[String: Any]] else { return [] }

        let threads = rows.compactMap { row -> AgentThread? in
            guard let id = row["id"] as? String else { return nil }
            if row["isHiddenFromSidebar"] as? Bool == true { return nil }
            let name = (row["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (row["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let activityMs = (row["lastActivityAt"] as? Double)
                ?? (row["updatedAt"] as? Double)
            // The bot's own name is the thread identity; the project title is
            // context. A nameless agent borrows the project title (no duplicate).
            let botName = name?.isEmpty == false ? name : nil
            let project = title?.isEmpty == false ? title : nil
            let awaiting = row["awaitingUserResponse"] as? [String: Any]
            return AgentThread(
                id: id,
                title: JSONLParsers.clean(botName ?? project ?? "Agent"),
                lastActivity: activityMs
                    .map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast,
                subtitle: botName != nil ? project : nil,
                cwd: nil,
                // "Why is this agent blocked" is the best recap Grok offers.
                recap: (awaiting?["reason"] as? String)
                    .flatMap { $0.isEmpty ? nil : JSONLParsers.clean($0, limit: 200) },
                isWaitingOnYou: awaiting != nil)
        }
        let sorted = threads.sorted {
            ($0.isWaitingOnYou ? 1 : 0, $0.lastActivity.timeIntervalSince1970)
                > ($1.isWaitingOnYou ? 1 : 0, $1.lastActivity.timeIntervalSince1970)
        }
        return Array(sorted.prefix(cap))
    }
}
