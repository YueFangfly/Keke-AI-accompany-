import Foundation

/// 整包备份导出。
///
/// **格式是 JSONL**：第一行是清单，后面每行一个文件条目。不用「一个大 JSON」，
/// 是因为一份带图的备份可能上百 MB——整个拼在内存里再序列化，在手机上会被系统直接杀掉。
/// 一行一个对象的话，导出时写完一行就能丢掉，将来做导入也能一行一行读。
///
/// **不含 API Key。** Key 都在 Keychain 里，本来就读不到；
/// UserDefaults 那部分还额外按名字过滤了一遍，作为第二道防线——
/// 一是防以后有人又把密钥写进偏好设置，二是老版本留下的明文
/// （`eleven_api_key` / `gh_token`）在迁进 Keychain 之前也不能跟着备份走。
enum BackupService {

    static let formatName = "keke-backup"
    static let formatVersion = 1
    static let fileExtension = "kekebak"

    /// 单个文件的大小上限。超过的跳过并在清单里记一笔——
    /// base64 要把整个文件读进内存，几百 MB 的东西不值得为它冒 OOM 的险
    static let maxFileBytes = 25 * 1024 * 1024

    // MARK: - 清单

    struct Manifest: Codable {
        var format = BackupService.formatName
        var version = BackupService.formatVersion
        var createdAt: Date
        var includesMedia: Bool
        /// 收进来的文件数
        var fileCount: Int
        /// 因为超过大小上限被跳过的文件名
        var skipped: [String]
        var totalBytes: Int
    }

    struct Entry: Codable {
        /// 相对 Documents 的路径。恢复时按这个路径写回去
        let path: String
        /// utf8 / base64。文本直接存原文，可读性好；二进制才 base64
        let encoding: String
        let bytes: Int
        let content: String
    }

    /// 导出的结果
    struct Result {
        let url: URL
        let manifest: Manifest
    }

    // MARK: - 收集要备份的文件

    /// UserDefaults 里**不**进备份的键。
    ///
    /// 前两个是明确的密钥；后面按子串兜底，免得以后新增的密钥漏网。
    /// 宁可少备份一个偏好设置，也不能让 key 跟着备份文件流出去
    private static let secretKeyMarkers = ["api_key", "apikey", "_key", "token", "secret", "password"]
    private static let secretKeyExact = ["ai_api_keys", "eleven_api_key"]

    /// 这些后缀的顶层文件算"数据"，都要备份
    private static let dataExtensions = ["json", "jsonl", "sqlite3", "sqlite3-wal", "sqlite3-shm"]
    /// 这些子目录是媒体，跟着 includeMedia 走
    private static let mediaDirectories = ["attachments", "Stickers", "Audio"]

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 列出要备份的文件（相对路径）。分成数据和媒体两拨，UI 上好分别估体积
    static func inventory(includeMedia: Bool) -> [String] {
        let fm = FileManager.default
        var paths: [String] = []

        if let top = try? fm.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
            for url in top {
                let name = url.lastPathComponent
                guard dataExtensions.contains(where: { name.hasSuffix("." + $0) }) else { continue }
                paths.append(name)
            }
        }
        guard includeMedia else { return paths.sorted() }

        for dir in mediaDirectories {
            let base = documents.appendingPathComponent(dir, isDirectory: true)
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let url as URL in walker {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                // 拼回相对 Documents 的路径。不用 relativePath——
                // enumerator 给的是绝对 URL，relativePath 在这里等于绝对路径
                let full = url.standardizedFileURL.path
                let root = documents.standardizedFileURL.path
                guard full.hasPrefix(root) else { continue }
                paths.append(String(full.dropFirst(root.count).drop(while: { $0 == "/" })))
            }
        }
        return paths.sorted()
    }

    /// 估算备份体积（字节）。base64 会把二进制撑大 4/3，估的时候要算进去
    static func estimatedSize(includeMedia: Bool) -> Int {
        var total = 0
        for path in inventory(includeMedia: includeMedia) {
            let url = documents.appendingPathComponent(path)
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard bytes <= maxFileBytes else { continue }
            total += isTextPath(path) ? bytes : bytes * 4 / 3
        }
        return total
    }

    /// 文本还是二进制。文本原样存进备份，方便用文本编辑器直接看
    private static func isTextPath(_ path: String) -> Bool {
        path.hasSuffix(".json") || path.hasSuffix(".jsonl")
    }

    // MARK: - 导出

    /// 生成备份文件，返回临时目录里的 URL。
    /// 会读一堆文件，**别在主线程调**。
    static func export(includeMedia: Bool, now: Date = Date()) throws -> Result {
        let fm = FileManager.default
        let name = "keke-backup-\(Self.stamp(now)).\(fileExtension)"
        let url = fm.temporaryDirectory.appendingPathComponent(name)
        try? fm.removeItem(at: url)
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw BackupError.cannotCreateFile(url.lastPathComponent)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        // 清单要写在第一行，但文件数和跳过列表得全写完才知道。
        // 所以先占一行位置，正文写完再回填——比"先在内存里攒齐所有文件"省得多
        let placeholder = String(repeating: " ", count: 512)
        try handle.write(contentsOf: Data((placeholder + "\n").utf8))

        var written = 0
        var skipped: [String] = []
        var totalBytes = 0

        for path in inventory(includeMedia: includeMedia) {
            let fileURL = documents.appendingPathComponent(path)
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= maxFileBytes else { skipped.append(path); continue }
            guard let data = try? Data(contentsOf: fileURL) else { skipped.append(path); continue }

            let entry: Entry
            if isTextPath(path), let text = String(data: data, encoding: .utf8) {
                entry = Entry(path: path, encoding: "utf8", bytes: data.count, content: text)
            } else {
                entry = Entry(path: path, encoding: "base64", bytes: data.count,
                              content: data.base64EncodedString())
            }
            guard var line = try? JSONEncoder().encode(entry) else { skipped.append(path); continue }
            line.append(0x0A)
            try handle.write(contentsOf: line)
            written += 1
            totalBytes += data.count
        }

        // 偏好设置作为一个合成条目，路径用一个真实文件不可能重名的名字
        if let prefs = userDefaultsEntry() {
            var line = try JSONEncoder().encode(prefs)
            line.append(0x0A)
            try handle.write(contentsOf: line)
            written += 1
            totalBytes += prefs.bytes
        }

        let manifest = Manifest(createdAt: now, includesMedia: includeMedia,
                                fileCount: written, skipped: skipped, totalBytes: totalBytes)
        try rewriteFirstLine(of: url, with: manifest, width: placeholder.count)
        return Result(url: url, manifest: manifest)
    }

    /// 把开头那行占位符换成真正的清单。
    /// 清单一定比占位短（跳过列表极少），短了就用空格补齐，行长不变，
    /// 这样只改开头这一段，不用把后面几百 MB 全部搬一遍
    private static func rewriteFirstLine(of url: URL, with manifest: Manifest, width: Int) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = String(decoding: try encoder.encode(manifest), as: UTF8.self)
        if json.utf8.count > width {
            // 跳过列表太长撑爆了占位行，那就只留数量，别把文件写坏
            var trimmed = manifest
            trimmed.skipped = ["\(manifest.skipped.count) files skipped"]
            json = String(decoding: try encoder.encode(trimmed), as: UTF8.self)
        }
        let padding = max(0, width - json.utf8.count)
        let line = json + String(repeating: " ", count: padding)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data(line.utf8))
    }

    /// 偏好设置。过滤掉一切看着像密钥的键
    private static func userDefaultsEntry() -> Entry? {
        var safe: [String: Any] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            // dictionaryRepresentation 会把系统自己的偏好（AppleLanguages、
            // NSInterfaceStyle、WebKit 那一堆）也一起给出来。它们跟这个 App 无关，
            // 白占体积，将来做恢复时写回去还可能把系统设置改坏
            guard !isSystemKey(key) else { continue }
            guard !isSecretKey(key) else { continue }
            // Data / Date 这些 JSONSerialization 认不了的直接跳过——
            // 它们要么是能重新算出来的缓存，要么在别的文件里已经有一份
            guard JSONSerialization.isValidJSONObject([value]) else { continue }
            safe[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return Entry(path: preferencesPath, encoding: "utf8", bytes: data.count, content: text)
    }

    private static let systemKeyPrefixes = ["Apple", "NS", "com.apple.", "WebKit", "AK", "INNextFreshness"]

    static func isSystemKey(_ key: String) -> Bool {
        systemKeyPrefixes.contains(where: key.hasPrefix)
    }

    static func isSecretKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        if secretKeyExact.contains(lower) { return true }
        return secretKeyMarkers.contains(where: lower.contains)
    }

    // MARK: - 杂项

    /// 文件名里的时间戳。用固定的 en_US_POSIX + 无分隔符格式，
    /// 免得跟着系统区域设置变出斜杠之类没法当文件名的字符
    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: date)
    }

    static func humanSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
        return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
}

enum BackupError: LocalizedError {
    case cannotCreateFile(String)
    case cannotRead
    case notABackup
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let name):
            return "写不了备份文件 \(name)，可能是存储空间不够"
        case .cannotRead:
            return "读不了这个文件，可能没有权限或者文件已经被移走了"
        case .notABackup:
            return "这不是克克的备份文件"
        case .unsupportedVersion(let v):
            return "这份备份是更新版本的 App 导出的（格式 v\(v)），当前版本读不了"
        }
    }
}

// MARK: - 恢复

/// 从备份恢复。
///
/// **分两步，中间隔一次启动。** 直接把文件写回 Documents 是不行的：
/// ChatStore、MemoryService 这十几个 Store 内存里还拿着旧数据，
/// 下一次自动保存就把刚恢复的内容盖回去了——用户会以为恢复失败，
/// 实际是被自己覆盖的。
///
/// 所以第一步只把内容解到暂存目录，第二步在 App 启动时、任何 Store 建出来之前
/// 才真正搬进 Documents（在 `KekeApp.init()` 里调）。
extension BackupService {

    struct RestoreReport {
        let manifest: Manifest
        /// 解出来待应用的文件数
        let staged: Int
        /// 路径不合法被拒的条目。正常备份不该有，有就说明文件被改过
        let rejected: [String]
    }

    private static var stagingDir: URL {
        documents.appendingPathComponent("_restore_pending", isDirectory: true)
    }
    /// 上一次恢复时被换下来的旧数据。留一份，恢复错了还能找回来
    private static var previousDir: URL {
        documents.appendingPathComponent("_pre_restore", isDirectory: true)
    }
    private static let pendingFlag = "keke_restore_pending"

    static let preferencesPath = "__preferences__.json"

    /// 备份里出现的这些路径一律拒绝：绝对路径、跳出目录、以及我们自己的两个内部目录。
    /// 备份文件是从外面导进来的，路径不能直接信
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(".."), !parts.contains(".") , !parts.contains("") else { return false }
        guard !parts.contains("_restore_pending"), !parts.contains("_pre_restore") else { return false }
        return true
    }

    /// 只读第一行拿清单，用来在确认之前告诉用户这是哪天的备份、多大。
    /// 不解正文——用户可能只是想看一眼
    static func inspect(_ url: URL) throws -> Manifest {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw BackupError.cannotRead }
        defer { try? handle.close() }
        guard let head = try handle.read(upToCount: 4096), !head.isEmpty,
              let newline = head.firstIndex(of: 0x0A) else { throw BackupError.notABackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: head[head.startIndex..<newline]),
              manifest.format == formatName else { throw BackupError.notABackup }
        guard manifest.version <= formatVersion else {
            throw BackupError.unsupportedVersion(manifest.version)
        }
        return manifest
    }

    /// 把备份解到暂存目录。**这一步不动任何现有数据**，
    /// 中途失败顶多留下一个没用的暂存目录，下次恢复会先清掉
    static func stageRestore(from url: URL) throws -> RestoreReport {
        let manifest = try inspect(url)
        let fm = FileManager.default
        try? fm.removeItem(at: stagingDir)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw BackupError.cannotRead }
        defer { try? handle.close() }

        var staged = 0
        var rejected: [String] = []
        var isFirstLine = true

        readLines(handle) { line in
            // 第一行是清单，inspect 已经解过了
            if isFirstLine { isFirstLine = false; return }
            guard let entry = try? JSONDecoder().decode(Entry.self, from: line) else { return }
            guard isSafeRelativePath(entry.path) else { rejected.append(entry.path); return }

            let data: Data?
            switch entry.encoding {
            case "utf8": data = Data(entry.content.utf8)
            case "base64": data = Data(base64Encoded: entry.content)
            default: data = nil
            }
            guard let data else { rejected.append(entry.path); return }

            let target = stagingDir.appendingPathComponent(entry.path)
            try? fm.createDirectory(at: target.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            guard (try? data.write(to: target, options: .atomic)) != nil else {
                rejected.append(entry.path); return
            }
            staged += 1
        }

        guard staged > 0 else {
            try? fm.removeItem(at: stagingDir)
            throw BackupError.notABackup
        }
        UserDefaults.standard.set(true, forKey: pendingFlag)
        return RestoreReport(manifest: manifest, staged: staged, rejected: rejected)
    }

    /// 有没有一份等着下次启动应用的恢复
    static var hasPendingRestore: Bool {
        UserDefaults.standard.bool(forKey: pendingFlag)
    }

    /// 取消一份还没应用的恢复
    static func cancelPendingRestore() {
        try? FileManager.default.removeItem(at: stagingDir)
        UserDefaults.standard.removeObject(forKey: pendingFlag)
    }

    /// **在 `KekeApp.init()` 里调，早于任何 Store 的构造。**
    /// 没有待应用的恢复时，开销就是一次 bool 读取
    static func applyPendingRestore() {
        guard hasPendingRestore else { return }
        // 无论下面成不成，标记先清掉：真失败了也不能让它每次启动都重试一遍
        UserDefaults.standard.removeObject(forKey: pendingFlag)

        let fm = FileManager.default
        guard let walker = fm.enumerator(at: stagingDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            try? fm.removeItem(at: stagingDir)
            return
        }
        // 换下来的旧数据挪到一边而不是删掉。同一个卷上这是改名，不占额外空间，
        // 恢复错了还能捞回来。只留最近一次
        try? fm.removeItem(at: previousDir)
        try? fm.createDirectory(at: previousDir, withIntermediateDirectories: true)

        let stagingPath = stagingDir.standardizedFileURL.path
        for case let source as URL in walker {
            guard (try? source.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let full = source.standardizedFileURL.path
            guard full.hasPrefix(stagingPath) else { continue }
            let relative = String(full.dropFirst(stagingPath.count).drop(while: { $0 == "/" }))
            guard isSafeRelativePath(relative) else { continue }

            if relative == preferencesPath {
                applyPreferences(at: source)
                continue
            }
            let destination = documents.appendingPathComponent(relative)
            if fm.fileExists(atPath: destination.path) {
                let kept = previousDir.appendingPathComponent(relative)
                try? fm.createDirectory(at: kept.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                try? fm.moveItem(at: destination, to: kept)
            }
            try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? fm.moveItem(at: source, to: destination)
        }
        try? fm.removeItem(at: stagingDir)
    }

    /// 偏好设置单独处理：它不是一个真文件，要一条条写回 UserDefaults。
    /// 进来的时候**再过滤一遍**密钥和系统键——备份是从外面来的，
    /// 就算是自己导出的也不能假设中间没被人改过
    private static func applyPreferences(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        for (key, value) in dict {
            guard !isSystemKey(key), !isSecretKey(key) else { continue }
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    /// 按行读，每行交给 body。分块读是为了让内存占用只跟**单行**大小相关，
    /// 而不是跟整个备份大小相关——备份可能有几百 MB
    private static func readLines(_ handle: FileHandle, _ body: (Data) -> Void) {
        var buffer = Data()
        while true {
            guard let chunk = (try? handle.read(upToCount: 1 << 20)) ?? nil, !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                if !line.isEmpty { body(Data(line)) }
                buffer = Data(buffer[buffer.index(after: newline)...])
            }
        }
        if !buffer.isEmpty { body(buffer) }
    }
}
