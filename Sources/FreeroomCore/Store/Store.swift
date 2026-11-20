import Foundation
import SQLite3

public enum StoreError: Error, CustomStringConvertible {
    case open(String), sql(String)
    public var description: String {
        switch self {
        case .open(let m): "cannot open database: \(m)"
        case .sql(let m): "database error: \(m)"
        }
    }
}

public struct ScanRecord: Codable, Equatable, Sendable {
    public var id: String
    public var source: FindingSource
    public var startedAt: Date
    public var endedAt: Date?
    public var note: String?
}

public struct HistoryEntry: Codable, Equatable, Sendable {
    public var findingId: String
    public var title: String
    public var freedBytes: Int64
    public var at: Date
    /// Where the cleanup was started: "agent-scan", "menu", "notification", "cli".
    public var origin: String
}

/// Local SQLite store shared by the CLI (writer) and the app (reader + cleaner).
/// WAL mode lets the app read while the CLI writes.
public final class Store: @unchecked Sendable {
    private var db: OpaquePointer?
    public let path: String

    public static var defaultPath: String {
        if let override = ProcessInfo.processInfo.environment["FREEROOM_DB"], !override.isEmpty {
            return PathUtils.expand(override)
        }
        return PathUtils.expand("~/Library/Application Support/Freeroom/freeroom.db")
    }

    public init(path: String = Store.defaultPath) throws {
        self.path = path
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_busy_timeout(db, 5000)
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
        CREATE TABLE IF NOT EXISTS scans(
            id TEXT PRIMARY KEY, source TEXT NOT NULL, started_at REAL NOT NULL, ended_at REAL, note TEXT);
        CREATE TABLE IF NOT EXISTS findings(
            scan_id TEXT NOT NULL, id TEXT NOT NULL, source TEXT NOT NULL, safety TEXT NOT NULL,
            size INTEGER NOT NULL, json TEXT NOT NULL, created_at REAL NOT NULL,
            PRIMARY KEY(scan_id, id));
        CREATE TABLE IF NOT EXISTS history(
            id INTEGER PRIMARY KEY AUTOINCREMENT, finding_id TEXT NOT NULL, title TEXT NOT NULL,
            freed INTEGER NOT NULL, at REAL NOT NULL, origin TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS translations(
            finding_id TEXT NOT NULL, lang TEXT NOT NULL, text TEXT NOT NULL, at REAL NOT NULL,
            PRIMARY KEY(finding_id, lang));
        PRAGMA user_version = 1;
        """)
    }

    deinit { sqlite3_close(db) }

    // MARK: Scans

    @discardableResult
    public func beginScan(source: FindingSource, note: String? = nil) throws -> ScanRecord {
        let record = ScanRecord(id: Self.newScanId(), source: source, startedAt: Date(), endedAt: nil, note: note)
        try run("INSERT INTO scans(id, source, started_at, note) VALUES(?,?,?,?)",
                [.text(record.id), .text(source.rawValue), .real(record.startedAt.timeIntervalSince1970), note.map { .text($0) } ?? .null])
        return record
    }

    public func endScan(id: String) throws {
        try run("UPDATE scans SET ended_at = ? WHERE id = ?", [.real(Date().timeIntervalSince1970), .text(id)])
    }

    public func scans(limit: Int = 20) throws -> [ScanRecord] {
        try query("SELECT id, source, started_at, ended_at, note FROM scans ORDER BY started_at DESC LIMIT ?", [.int(Int64(limit))]) { s in
            ScanRecord(id: s.text(0) ?? "", source: FindingSource(rawValue: s.text(1) ?? "") ?? .rule,
                       startedAt: Date(timeIntervalSince1970: s.double(2)),
                       endedAt: s.isNull(3) ? nil : Date(timeIntervalSince1970: s.double(3)),
                       note: s.text(4))
        }
    }

    /// Most recent scan still open (no end time), optionally for one source.
    public func openScan(source: FindingSource? = nil) throws -> ScanRecord? {
        try scans(limit: 50).first { $0.endedAt == nil && (source == nil || $0.source == source) }
    }

    // MARK: Findings

    public func upsert(_ finding: Finding, scanId: String) throws {
        var f = finding
        f.scanId = scanId
        let json = String(decoding: try JSONEncoder.freeroom.encode(f), as: UTF8.self)
        try run("""
        INSERT INTO findings(scan_id, id, source, safety, size, json, created_at) VALUES(?,?,?,?,?,?,?)
        ON CONFLICT(scan_id, id) DO UPDATE SET source=excluded.source, safety=excluded.safety,
            size=excluded.size, json=excluded.json
        """, [.text(scanId), .text(f.id), .text(f.source.rawValue), .text(f.safety.rawValue),
              .int(f.sizeBytes), .text(json), .real(Date().timeIntervalSince1970)])
    }

    public func findings(scanId: String) throws -> [Finding] {
        try query("SELECT json FROM findings WHERE scan_id = ? ORDER BY size DESC", [.text(scanId)]) { s in
            try JSONDecoder.freeroom.decode(Finding.self, from: Data((s.text(0) ?? "").utf8))
        }
    }

    /// Findings of the latest scan of each source (rule + agent), newest first.
    public func latestFindings() throws -> [Finding] {
        var result: [Finding] = []
        for source in [FindingSource.agent, .rule] {
            if let scan = try scans(limit: 50).first(where: { $0.source == source }) {
                result += try findings(scanId: scan.id)
            }
        }
        return result.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: Translations (explanations are stored in English; translations on demand)

    public func setTranslation(findingId: String, lang: String, text: String) throws {
        try run("""
        INSERT INTO translations(finding_id, lang, text, at) VALUES(?,?,?,?)
        ON CONFLICT(finding_id, lang) DO UPDATE SET text=excluded.text, at=excluded.at
        """, [.text(findingId), .text(lang), .text(text), .real(Date().timeIntervalSince1970)])
    }

    public func translations(lang: String) throws -> [String: String] {
        let pairs = try query("SELECT finding_id, text FROM translations WHERE lang = ?", [.text(lang)]) { s in
            (s.text(0) ?? "", s.text(1) ?? "")
        }
        return Dictionary(pairs, uniquingKeysWith: { _, last in last })
    }

    // MARK: History

    public func recordCleanup(_ entry: HistoryEntry) throws {
        try run("INSERT INTO history(finding_id, title, freed, at, origin) VALUES(?,?,?,?,?)",
                [.text(entry.findingId), .text(entry.title), .int(entry.freedBytes),
                 .real(entry.at.timeIntervalSince1970), .text(entry.origin)])
    }

    public func history(limit: Int = 100) throws -> [HistoryEntry] {
        try query("SELECT finding_id, title, freed, at, origin FROM history ORDER BY at DESC LIMIT ?", [.int(Int64(limit))]) { s in
            HistoryEntry(findingId: s.text(0) ?? "", title: s.text(1) ?? "", freedBytes: s.int(2),
                         at: Date(timeIntervalSince1970: s.double(3)), origin: s.text(4) ?? "")
        }
    }

    // MARK: SQLite plumbing

    enum Value { case text(String), int(Int64), real(Double), null }

    struct Row {
        let stmt: OpaquePointer
        func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(db)))
        }
        for (i, value) in values.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, Self.transient)
            case .int(let n): sqlite3_bind_int64(stmt, idx, n)
            case .real(let d): sqlite3_bind_double(stmt, idx, d)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.sql(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query<T>(_ sql: String, _ values: [Value], _ map: (Row) throws -> T) throws -> [T] {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        var rows: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw StoreError.sql(String(cString: sqlite3_errmsg(db))) }
            rows.append(try map(Row(stmt: stmt)))
        }
        return rows
    }

    static func newScanId() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "scan-\(f.string(from: Date()))-\(UUID().uuidString.prefix(4).lowercased())"
    }
}

public extension JSONEncoder {
    static var freeroom: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

public extension JSONDecoder {
    static var freeroom: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
