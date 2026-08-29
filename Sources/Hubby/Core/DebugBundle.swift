import AppKit
import Foundation

/// "Report a problem…": writes a redacted diagnostic folder to the Desktop
/// and opens the new-issue page. Everything in the bundle is generated
/// locally and shown to the user before THEY choose to attach it — Hubby
/// itself sends nothing anywhere.
///
/// Redaction rules: the home directory collapses to `~`, and any other
/// /Users/<name> prefix is anonymized. Thread titles and working
/// directories never appear at all — only counts and availability.
enum DebugBundle {
    static let newIssueURL = URL(
        string: "https://github.com/lennoxsaint/hubby/issues/new?template=bug-report.yml")!

    static var crashLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Hubby/crash.log")
    }

    /// Collapse the user's identity out of any path-bearing text.
    static func redact(
        _ text: String,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        var out = text.replacingOccurrences(of: home, with: "~")
        // Any other user's prefix (shared machines, odd mounts).
        while let range = out.range(
            of: #"/Users/[^/\s"']+"#, options: .regularExpression) {
            out.replaceSubrange(range, with: "~")
        }
        return out
    }

    /// The report body: versions, per-adapter availability + counts, AX
    /// state. Pure function of its inputs so tests can pin the redaction.
    static func report(
        snapshots: [AgentSnapshot],
        appVersion: String,
        osVersion: String,
        axTrusted: Bool,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        var lines = [
            "Hubby debug bundle",
            "generated: \(ISO8601DateFormatter().string(from: Date()))",
            "app: \(appVersion)",
            "macOS: \(osVersion)",
            "accessibility (exact jumps): \(axTrusted ? "granted" : "not granted")",
            "",
            "adapters:",
        ]
        for snapshot in snapshots {
            let threads = snapshot.threads
            lines.append(
                "  \(snapshot.info.id): running=\(snapshot.isRunning) " +
                "threads=\(threads.count) generating=\(snapshot.runningCount) " +
                "needsYou=\(snapshot.needsYouCount) unread=\(snapshot.unreadCount)")
        }
        return redact(lines.joined(separator: "\n") + "\n", home: home)
    }

    /// Write the bundle folder to the Desktop and reveal it, then open the
    /// prefilled new-issue page. Returns the folder URL (nil on failure).
    @MainActor
    @discardableResult
    static func writeAndReveal(snapshots: [AgentSnapshot]) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/hubby-debug-\(stamp)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
            let os = ProcessInfo.processInfo.operatingSystemVersionString
            let body = report(
                snapshots: snapshots, appVersion: AppVersion.short,
                osVersion: os, axTrusted: WindowLocator.isTrusted)
            try body.write(
                to: dir.appendingPathComponent("hubby-report.txt"),
                atomically: true, encoding: .utf8)
            // Recent crashes ride along, redacted like everything else.
            if let crashes = try? String(contentsOf: crashLogURL, encoding: .utf8) {
                try redact(crashes).write(
                    to: dir.appendingPathComponent("crash.log"),
                    atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([dir])
            NSWorkspace.shared.open(newIssueURL)
            return dir
        } catch {
            NSLog("Debug bundle write failed: \(error)")
            return nil
        }
    }

    /// Install once at launch: uncaught exceptions leave a stack in
    /// ~/Library/Logs/Hubby/crash.log so bug reports carry evidence.
    static func installCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            let entry = "\n[\(Date())] \(exception.name.rawValue): " +
                "\(exception.reason ?? "-")\n\(stack)\n"
            let url = DebugBundle.crashLogURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(entry.utf8))
                try? handle.close()
            } else {
                try? entry.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
