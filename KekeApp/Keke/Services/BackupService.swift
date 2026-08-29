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
        return Entry(path: "__preferences__.json", encoding: "utf8", bytes: data.count, content: text)
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

    var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let name):
            return "写不了备份文件 \(name)，可能是存储空间不够"
        }
    }
}
