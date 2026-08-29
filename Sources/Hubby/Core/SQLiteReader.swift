import Foundation
import SQLite3

/// Shared read-only SQLite access. Hubby never takes a lock on another app's
/// database: snapshot databases open with `immutable=1`; live-WAL databases
/// open plain read-only (immutable would return stale/corrupt WAL reads),
/// falling back to a temp copy of db+wal+shm if the direct open fails.
enum SQLiteReader {
    enum Mode {
        /// The database is not being written while we read (or staleness is
        /// fine): `immutable=1`, guaranteed zero locking.
        case immutable
        /// The owner writes via WAL continuously; open plain read-only.
        case liveWAL
    }

    struct Row {
        let values: [Any?] // String, Int64, Double, or nil per column

        func string(_ index: Int) -> String? { values[index] as? String }
        func int64(_ index: Int) -> Int64? { values[index] as? Int64 }
        func double(_ index: Int) -> Double? {
            (values[index] as? Double) ?? (values[index] as? Int64).map(Double.init)
        }
    }

    static func query(_ databaseURL: URL, mode: Mode, sql: String) -> [Row]? {
        if let rows = run(sql, at: databaseURL, immutable: mode == .immutable) {
            return rows
        }
        guard mode == .liveWAL else { return nil }
        // Error path only: copy db+wal+shm to temp and read the copy.
        guard let copy = tempCopy(of: databaseURL) else { return nil }
        return run(sql, at: copy, immutable: true)
    }

    private static func run(_ sql: String, at url: URL, immutable: Bool) -> [Row]? {
        var db: OpaquePointer?
        let uri = "file:\(url.path)?mode=ro\(immutable ? "&immutable=1" : "")"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                let count = sqlite3_column_count(statement)
                var values: [Any?] = []
                for column in 0..<count {
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER:
                        values.append(sqlite3_column_int64(statement, column))
                    case SQLITE_FLOAT:
                        values.append(sqlite3_column_double(statement, column))
                    case SQLITE_TEXT:
                        values.append(sqlite3_column_text(statement, column)
                            .map { String(cString: $0) })
                    default:
                        values.append(nil)
                    }
                }
                rows.append(Row(values: values))
            } else if step == SQLITE_DONE {
                return rows
            } else {
                return nil // busy/corrupt mid-read: let the caller fall back
            }
        }
    }

    /// Copy db + sidecars to the temp dir and read the copy. ONE dir per
    /// source database (keyed by path hash), refreshed in place only when
    /// the source changed — a per-stamp dir scheme once piled up gigabytes
    /// of a 187MB Hermes db and stalled first paint behind the copies.
    /// The change stamp folds in the -wal's size+mtime (ms): the wal grows
    /// without necessarily bumping the main file's whole-second mtime, and
    /// that once served stale same-second reads.
    private static func tempCopy(of url: URL) -> URL? {
        let fm = FileManager.default
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)?.timeIntervalSince1970 ?? 0
        let walAttrs = try? fm.attributesOfItem(atPath: url.path + "-wal")
        let walSize = (walAttrs?[.size] as? Int) ?? 0
        let walMtime = (walAttrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let stamp = "\(Int(mtime * 1000))-\(walSize)-\(Int(walMtime * 1000))"

        let dir = fm.temporaryDirectory
            .appendingPathComponent("hubby-sqlite-\(abs(url.path.hashValue))")
        let copy = dir.appendingPathComponent(url.lastPathComponent)
        let stampFile = dir.appendingPathComponent(".stamp")
        if fm.fileExists(atPath: copy.path) {
            if (try? String(contentsOf: stampFile, encoding: .utf8)) == stamp {
                return copy
            }
            // Huge databases: a slightly stale copy beats recopying
            // hundreds of MB on every refresh tick. Recopy at most every
            // 10 minutes; small databases refresh immediately.
            let sourceSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let copyAge = (try? fm.attributesOfItem(atPath: copy.path)[.creationDate] as? Date)
                .map { Date().timeIntervalSince($0) } ?? .infinity
            if (sourceSize ?? 0) > 64 * 1024 * 1024, copyAge < 600 {
                return copy
            }
        }
        do {
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: copy)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: url.path + suffix)
                if fm.fileExists(atPath: sidecar.path) {
                    try? fm.copyItem(
                        at: sidecar,
                        to: dir.appendingPathComponent(sidecar.lastPathComponent))
                }
            }
            try? stamp.write(to: stampFile, atomically: true, encoding: .utf8)
            return copy
        } catch {
            try? fm.removeItem(at: dir)
            return nil
        }
    }
}
