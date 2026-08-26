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
        let values: [Any?] // String, Int64, or nil per column

        func string(_ index: Int) -> String? { values[index] as? String }
        func int64(_ index: Int) -> Int64? { values[index] as? Int64 }
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

    /// Copy db + sidecars to the temp dir, cached per (path, mtime) so
    /// repeated failures don't recopy a large file.
    private static func tempCopy(of url: URL) -> URL? {
        let fm = FileManager.default
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)?.timeIntervalSince1970 ?? 0
        let stamp = "\(abs(url.path.hashValue))-\(Int(mtime))"
        let dir = fm.temporaryDirectory.appendingPathComponent("hubby-sqlite-\(stamp)")
        let copy = dir.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: copy.path) { return copy }
        do {
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
            return copy
        } catch {
            try? fm.removeItem(at: dir)
            return nil
        }
    }
}
