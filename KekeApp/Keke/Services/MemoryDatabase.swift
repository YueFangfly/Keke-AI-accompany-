import Foundation
import SQLite3

/// 长期记忆的 SQLite + FTS5 存储层。索引用 trigram 分词（对中文友好，
/// 不需要额外的分词器就能做子串级别的模糊匹配），检索排序用 FTS5 自带的 BM25，
/// 比之前手写的"二字组重合度"更准，也扛得住上万条记忆不卡。
/// 2026-07-17 参考 Ombre Brain 加了几个机制（检索算法不变）：
/// - 情绪坐标：valence（这事让她感觉多好/多糟 -1~1）+ arousal（情绪强度 0~1），强烈的事衰减慢
/// - 未解决状态：还没着落的事（快到的考试/约好的事）无条件带上、克克会主动惦记；了结后权重掉下去
/// - 唤醒计数：被检索想起的次数，越常想起记得越牢（艾宾浩斯"复习"的那一半）
/// - 归档：长期没被想起的旧事移出日常检索但不删，记忆页还能翻到、能捞回来
final class MemoryDatabase {
    enum Importance: String, Codable, CaseIterable {
        case normal, important, pinned
    }

    /// 这件事有没有"下文"：none = 普通事实；open = 还没着落（会被惦记）；resolved = 已经了结
    enum Status: String, Codable, CaseIterable {
        case none, open, resolved
    }

    struct Row: Identifiable, Equatable {
        var id: Int64
        var text: String
        var createdAt: Date
        var category: String
        var importance: Importance
        var valence: Double
        var arousal: Double
        var status: Status
        var recallCount: Int
        var archived: Bool
        var contact: String
    }

    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// 所有 SELECT 共用的列顺序，跟 readRow 一一对应
    private static let columns = "id, text, created_at, category, importance, valence, arousal, status, recall_count, archived, contact"

    init?(path: URL) {
        guard sqlite3_open(path.path, &db) == SQLITE_OK else { return nil }
        createTables()
        migrateColumnsIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - 建表

    private func createTables() {
        exec("""
        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            created_at REAL NOT NULL,
            category TEXT NOT NULL DEFAULT '',
            importance TEXT NOT NULL DEFAULT 'normal',
            valence REAL NOT NULL DEFAULT 0,
            arousal REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'none',
            recall_count INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0,
            contact TEXT NOT NULL DEFAULT 'keke'
        );
        """)

        // trigram 分词器要求系统 SQLite 版本够新（iOS 16 肯定够）；万一不支持，
        // 退回默认分词器，至少不会整个建表失败
        let usedTrigram = exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
            text, content='memories', content_rowid='id', tokenize='trigram'
        );
        """)
        if !usedTrigram {
            exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
                text, content='memories', content_rowid='id'
            );
            """)
        }

        exec("""
        CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
            INSERT INTO memories_fts(rowid, text) VALUES (new.id, new.text);
        END;
        """)
        exec("""
        CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
            INSERT INTO memories_fts(memories_fts, rowid, text) VALUES ('delete', old.id, old.text);
        END;
        """)
        exec("""
        CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
            INSERT INTO memories_fts(memories_fts, rowid, text) VALUES ('delete', old.id, old.text);
            INSERT INTO memories_fts(rowid, text) VALUES (new.id, new.text);
        END;
        """)
    }

    /// 老库（升级前建的表）没有新列：挨个 ALTER TABLE 补上，已存在的会失败、忽略即可
    private func migrateColumnsIfNeeded() {
        exec("ALTER TABLE memories ADD COLUMN valence REAL NOT NULL DEFAULT 0;")
        exec("ALTER TABLE memories ADD COLUMN arousal REAL NOT NULL DEFAULT 0;")
        exec("ALTER TABLE memories ADD COLUMN status TEXT NOT NULL DEFAULT 'none';")
        exec("ALTER TABLE memories ADD COLUMN recall_count INTEGER NOT NULL DEFAULT 0;")
        exec("ALTER TABLE memories ADD COLUMN archived INTEGER NOT NULL DEFAULT 0;")
        // 多窗口改造：记忆按联系人分区，老记忆全部归克克
        exec("ALTER TABLE memories ADD COLUMN contact TEXT NOT NULL DEFAULT 'keke';")
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    // MARK: - 写

    @discardableResult
    func insert(text: String, createdAt: Date = Date(), category: String = "",
               importance: Importance = .normal, valence: Double = 0, arousal: Double = 0,
               status: Status = .none, contact: String = "keke") -> Int64? {
        let sql = """
        INSERT INTO memories (text, created_at, category, importance, valence, arousal, status, contact)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, text, -1, transient)
        sqlite3_bind_double(stmt, 2, createdAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, category, -1, transient)
        sqlite3_bind_text(stmt, 4, importance.rawValue, -1, transient)
        sqlite3_bind_double(stmt, 5, min(max(valence, -1), 1))
        sqlite3_bind_double(stmt, 6, min(max(arousal, 0), 1))
        sqlite3_bind_text(stmt, 7, status.rawValue, -1, transient)
        sqlite3_bind_text(stmt, 8, contact, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return sqlite3_last_insert_rowid(db)
    }

    func delete(id: Int64) {
        let sql = "DELETE FROM memories WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    func delete(ids: [Int64]) {
        for id in ids { delete(id: id) }
    }

    func deleteAll() {
        exec("DELETE FROM memories;")
    }

    func setImportance(_ importance: Importance, for id: Int64) {
        updateColumn(sql: "UPDATE memories SET importance = ? WHERE id = ?;", value: importance.rawValue, id: id)
    }

    func setStatus(_ status: Status, for id: Int64) {
        updateColumn(sql: "UPDATE memories SET status = ? WHERE id = ?;", value: status.rawValue, id: id)
    }

    func setArchived(_ archived: Bool, for id: Int64) {
        let sql = "UPDATE memories SET archived = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, archived ? 1 : 0)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    private func updateColumn(sql: String, value: String, id: Int64) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, value, -1, transient)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    /// 这几条记忆被想起了一次（注入过上下文）：唤醒计数 +1，越常想起的事记得越牢
    func bumpRecall(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "UPDATE memories SET recall_count = recall_count + 1 WHERE id IN (\(placeholders));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        for (index, id) in ids.enumerated() {
            sqlite3_bind_int64(stmt, Int32(index + 1), id)
        }
        sqlite3_step(stmt)
    }

    /// 自动归档（本地规则，不花 AI 调用）：
    /// - 已了结的事过了 45 天 → 归档
    /// - 普通重要度、从来没被想起过、过了 120 天 → 归档
    /// 置顶/重要/还没了结的永远不自动归档。返回归档条数
    @discardableResult
    func autoArchive(now: Date = Date()) -> Int {
        let resolvedBefore = now.timeIntervalSince1970 - 45 * 86400
        let staleBefore = now.timeIntervalSince1970 - 120 * 86400
        let before = archivedCount
        exec("UPDATE memories SET archived = 1 WHERE archived = 0 AND status = 'resolved' AND created_at < \(resolvedBefore);")
        exec("""
        UPDATE memories SET archived = 1
        WHERE archived = 0 AND importance = 'normal' AND status = 'none'
          AND recall_count = 0 AND created_at < \(staleBefore);
        """)
        return archivedCount - before
    }

    // MARK: - 读

    var count: Int {
        scalarInt("SELECT COUNT(*) FROM memories;")
    }

    private var archivedCount: Int {
        scalarInt("SELECT COUNT(*) FROM memories WHERE archived = 1;")
    }

    private func scalarInt(_ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// 所有记忆（含归档），按时间新到旧；contact 传 nil 表示全部分区（给记忆页和维护用）
    func allRows(contact: String? = nil) -> [Row] {
        let filter = contact.map { "WHERE contact = '\(Self.escaped($0))'" } ?? ""
        return queryRows("SELECT \(Self.columns) FROM memories \(filter) ORDER BY created_at DESC;")
    }

    /// 没归档的记忆，按时间新到旧（日常检索都在这个范围里）
    func activeRows(contact: String = "keke") -> [Row] {
        queryRows("SELECT \(Self.columns) FROM memories WHERE archived = 0 AND contact = '\(Self.escaped(contact))' ORDER BY created_at DESC;")
    }

    /// 置顶级的记忆（雷点/约定），不管查什么都无条件带上，不占检索的名额
    func pinnedRows(contact: String = "keke") -> [Row] {
        queryRows("SELECT \(Self.columns) FROM memories WHERE importance = 'pinned' AND archived = 0 AND contact = '\(Self.escaped(contact))' ORDER BY created_at DESC;")
    }

    /// 还没了结的心事：也无条件带上（克克会惦记着），情绪重的排前面
    func openRows(contact: String = "keke", limit: Int = 6) -> [Row] {
        queryRows("""
        SELECT \(Self.columns) FROM memories WHERE status = 'open' AND archived = 0
          AND contact = '\(Self.escaped(contact))'
        ORDER BY arousal DESC, created_at DESC LIMIT \(limit);
        """)
    }

    /// contact id 只会是 "keke" 或 UUID 字符串，转义只是保险
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "''")
    }

    private func queryRows(_ sql: String) -> [Row] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(readRow(stmt))
        }
        return rows
    }

    /// 全文检索候选池，按 FTS5 的 BM25 相关度排序（越靠前越相关）。
    /// 排除置顶和未了结的（那两类单独无条件带上）、排除已归档的。
    /// candidateLimit 故意留宽松一些，方便外层再叠加时间衰减/情绪强度/唤醒次数重排
    func searchCandidates(query: String, contact: String = "keke", candidateLimit: Int = 80) -> [(row: Row, relevance: Double)] {
        // FTS5 MATCH 语法对一些符号敏感，简单清理一下避免查询语法出错
        let cleaned = query.filter { !"\"'*^:".contains($0) }
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let sql = """
        SELECT \(Self.columns.components(separatedBy: ", ").map { "m.\($0)" }.joined(separator: ", ")),
               bm25(memories_fts) AS score
        FROM memories_fts
        JOIN memories m ON m.id = memories_fts.rowid
        WHERE memories_fts MATCH ? AND m.importance != 'pinned' AND m.status != 'open' AND m.archived = 0
          AND m.contact = '\(Self.escaped(contact))'
        ORDER BY score ASC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, cleaned, -1, transient)
        sqlite3_bind_int64(stmt, 2, Int64(candidateLimit))

        var results: [(Row, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let row = readRow(stmt)
            // bm25 分数是负数、越负越相关；翻成正数、越大越相关，外层好处理
            let relevance = -sqlite3_column_double(stmt, 11)
            results.append((row, relevance))
        }
        return results
    }

    private func readRow(_ stmt: OpaquePointer?) -> Row {
        Row(
            id: sqlite3_column_int64(stmt, 0),
            text: columnText(stmt, 1),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
            category: columnText(stmt, 3),
            importance: Importance(rawValue: columnText(stmt, 4)) ?? .normal,
            valence: sqlite3_column_double(stmt, 5),
            arousal: sqlite3_column_double(stmt, 6),
            status: Status(rawValue: columnText(stmt, 7)) ?? .none,
            recallCount: Int(sqlite3_column_int64(stmt, 8)),
            archived: sqlite3_column_int64(stmt, 9) != 0,
            contact: columnText(stmt, 10)
        )
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }
}
