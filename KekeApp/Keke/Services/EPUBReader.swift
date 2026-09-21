import Foundation
import Compression

/// EPUB 正文抽取。
///
/// 加这个的理由很实际：**EPUB 就是电子书的格式**。原来只吃 pdf / txt / html / md，
/// 从微信读书、多看、Calibre、各种公众号排版工具导出来的东西全是 epub——
/// 「陪你一起看书」这个功能，一半的书根本导不进来。
///
/// 参考 `Youxuuuuu/co-reading-kit`、`EnhydrInk/tasogare` 那几个共读项目的做法：
/// 按 spine（阅读顺序）逐篇取正文，而不是把压缩包里的 xhtml 按文件名排一排——
/// 文件名排序在 `chapter10` 和 `chapter2` 上就会翻车。
///
/// iOS 上没有公开的 ZIP 读取 API，所以下面自己扒了一个最小实现：
/// 中央目录 + raw deflate（`COMPRESSION_ZLIB` 在 Apple 这边就是裸 DEFLATE，
/// 正好是 ZIP 用的那个），够读 epub 就行，不追求通用。
enum EPUBReader {

    /// 抽出整本书的正文。拿不到就回 nil，由调用方决定怎么说
    static func text(at url: URL) -> String? {
        guard let archive = try? Data(contentsOf: url) else { return nil }
        let bytes = [UInt8](archive)
        let entries = MiniZip.entries(in: bytes)
        guard !entries.isEmpty else { return nil }

        var byName: [String: MiniZip.Entry] = [:]
        for entry in entries { byName[entry.name] = entry }

        func read(_ name: String) -> String? {
            guard let entry = byName[name],
                  let data = MiniZip.extract(entry, from: bytes) else { return nil }
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        }

        // META-INF/container.xml 指向 opf；这一步是 epub 规范里唯一写死的路径
        guard let container = read("META-INF/container.xml"),
              let opfPath = attribute("full-path", inTagContaining: "rootfile", of: container)
        else { return nil }
        guard let opf = read(opfPath) else { return nil }

        let base = directory(of: opfPath)
        let manifest = manifestHrefs(opf)
        var chapters: [String] = []
        for id in spineOrder(opf) {
            guard let href = manifest[id] else { continue }
            guard let xhtml = read(resolve(href, relativeTo: base)) else { continue }
            let body = plainText(fromHTML: xhtml)
            if !body.isEmpty { chapters.append(body) }
        }
        // spine 读不出东西（少见但存在：有些工具导出的 opf 里 idref 对不上）
        // 就退回按压缩包里的顺序捞所有 xhtml。**顺序可能是乱的**，
        // 但有字看总比导不进来强
        if chapters.isEmpty {
            for entry in entries where isDocument(entry.name) {
                guard let data = MiniZip.extract(entry, from: bytes),
                      let xhtml = String(data: data, encoding: .utf8) else { continue }
                let body = plainText(fromHTML: xhtml)
                if !body.isEmpty { chapters.append(body) }
            }
        }

        let joined = chapters.joined(separator: "\n\n")
        return joined.isEmpty ? nil : joined
    }

    private static func isDocument(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".xhtml") || lower.hasSuffix(".html") || lower.hasSuffix(".htm")
    }

    // MARK: - opf

    /// manifest 里的 id → href
    static func manifestHrefs(_ opf: String) -> [String: String] {
        var out: [String: String] = [:]
        for tag in tags(named: "item", in: opf) {
            guard let id = attribute("id", in: tag), let href = attribute("href", in: tag) else { continue }
            out[id] = href
        }
        return out
    }

    /// spine 里的 idref 顺序，就是阅读顺序
    static func spineOrder(_ opf: String) -> [String] {
        tags(named: "itemref", in: opf).compactMap { attribute("idref", in: $0) }
    }

    /// 把 href 拼回压缩包里的完整路径。
    /// href 会有 `../`（opf 在 OEBPS/ 里、正文在 Text/ 里的排法很常见），
    /// 也会有 `%20` 这种转义，还可能带 `#锚点`——三样都得处理，
    /// 拼错了就是整章读不出来
    static func resolve(_ href: String, relativeTo base: String) -> String {
        var path = href
        if let hash = path.firstIndex(of: "#") { path = String(path[path.startIndex..<hash]) }
        path = path.removingPercentEncoding ?? path
        if path.hasPrefix("/") { return String(path.dropFirst()) }

        var parts = base.isEmpty ? [] : base.components(separatedBy: "/")
        for piece in path.components(separatedBy: "/") {
            switch piece {
            case "", ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(piece)
            }
        }
        return parts.joined(separator: "/")
    }

    private static func directory(of path: String) -> String {
        var parts = path.components(separatedBy: "/")
        guard parts.count > 1 else { return "" }
        parts.removeLast()
        return parts.joined(separator: "/")
    }

    // MARK: - 迷你 XML

    /// 取出所有 `<name …>` 开标签的原文。
    /// 不写正经 XML 解析器：opf 的结构很固定，而 `XMLParser` 是回调式的，
    /// 为了三个属性搭一整个 delegate 不划算
    static func tags(named name: String, in xml: String) -> [String] {
        var out: [String] = []
        var rest = Substring(xml)
        while let open = rest.range(of: "<\(name)", options: .caseInsensitive) {
            let after = rest[open.lowerBound...]
            // 确认是标签名本身而不是前缀（<item> vs <itemref>）
            let nameEnd = after.index(after.startIndex, offsetBy: name.count + 1)
            guard nameEnd < after.endIndex,
                  " \t\r\n/>".contains(after[nameEnd]) else {
                rest = rest[open.upperBound...]
                continue
            }
            guard let close = after.range(of: ">") else { break }
            out.append(String(after[after.startIndex..<close.upperBound]))
            rest = after[close.upperBound...]
        }
        return out
    }

    /// 取标签上的某个属性，单双引号都认
    static func attribute(_ key: String, in tag: String) -> String? {
        for quote in ["\"", "'"] {
            guard let keyRange = tag.range(of: "\(key)=\(quote)") else { continue }
            let after = tag[keyRange.upperBound...]
            guard let end = after.range(of: quote) else { continue }
            let value = String(after[after.startIndex..<end.lowerBound])
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func attribute(_ key: String, inTagContaining name: String, of xml: String) -> String? {
        tags(named: name, in: xml).compactMap { attribute(key, in: $0) }.first
    }

    // MARK: - xhtml → 正文

    /// 把一篇 xhtml 变成分好段的纯文字。
    ///
    /// **段落必须留住**：`BookService.paragraphs` 是按换行切段的，
    /// 要是像原来处理 html 那样把所有标签一律换成空格，
    /// 整本书会变成「一个段落」，进度、书签、批注定位全部失效
    static func plainText(fromHTML raw: String) -> String {
        var text = raw
        for pattern in [#"<script[\s\S]*?</script>"#,
                        #"<style[\s\S]*?</style>"#,
                        #"<head[\s\S]*?</head>"#,
                        #"<!--[\s\S]*?-->"#] {
            text = text.replacingOccurrences(of: pattern, with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        // 块级标签换成换行——段落就是靠这一步活下来的
        text = text.replacingOccurrences(
            of: #"</?(p|div|br|li|tr|h[1-6]|section|article|blockquote)[^>]*>"#,
            with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        // 行内压空格、行间最多留一个空行
        // 用 ICU 的 \x{...} 而不是 Swift 的 \u{...}：这是**原始字符串**，
        // \u{00A0} 不会被 Swift 转义，会原样丢给正则引擎，而 ICU 只认 \uhhhh 或 \x{hhhh}——
        // 写错了整条正则会失效，不报错，只是默默不生效
        text = text.replacingOccurrences(of: #"[ \t\x{00A0}]+"#, with: " ",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n[ \t]*"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 实体转义。`&amp;` 必须**最后**换：先换它的话，
    /// `&amp;lt;` 会先变成 `&lt;` 再被换成 `<`，等于凭空改了正文
    static func decodeEntities(_ raw: String) -> String {
        var text = raw
        // 数字实体（&#12345; / &#x4e2d;）
        text = replaceNumericEntities(text)
        for (entity, replacement) in [("&nbsp;", " "), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
                                      ("&lsquo;", "\u{2018}"), ("&rsquo;", "\u{2019}"),
                                      ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"),
                                      ("&hellip;", "\u{2026}"), ("&quot;", "\""),
                                      ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func replaceNumericEntities(_ raw: String) -> String {
        guard raw.contains("&#") else { return raw }
        var out = ""
        var rest = Substring(raw)
        while let start = rest.range(of: "&#") {
            out += rest[rest.startIndex..<start.lowerBound]
            let after = rest[start.upperBound...]
            guard let semicolon = after.range(of: ";"),
                  after.distance(from: after.startIndex, to: semicolon.lowerBound) <= 8 else {
                out += "&#"
                rest = after
                continue
            }
            var digits = Substring(after[after.startIndex..<semicolon.lowerBound])
            var radix = 10
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                digits = digits.dropFirst()
                radix = 16
            }
            if let code = UInt32(digits, radix: radix), let scalar = Unicode.Scalar(code) {
                out.append(Character(scalar))
            } else {
                out += rest[start.lowerBound..<semicolon.upperBound]
            }
            rest = after[semicolon.upperBound...]
        }
        return out + rest
    }
}

// MARK: - 最小 ZIP 读取

/// 只够读 epub 的 ZIP 实现。
///
/// iOS 没有公开的 ZIP 读取 API（`Compression` 只给单段压缩流，
/// `AppleArchive` 是另一种格式），而 epub 就是个 ZIP。
/// 这里只走**中央目录**——不去顺着文件头一个个爬，因为设了 data descriptor
/// 标志位的条目，本地头里的压缩长度是 0，爬着爬着就对不上了
enum MiniZip {

    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private static let eocdSignature: UInt32 = 0x0605_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let localSignature: UInt32 = 0x0403_4b50

    static func entries(in bytes: [UInt8]) -> [Entry] {
        guard let eocd = findEOCD(bytes) else { return [] }
        let count = Int(u16(bytes, eocd + 10))
        let directoryOffset = Int(u32(bytes, eocd + 16))
        // 这两个值撑满就说明是 zip64。epub 不会有 65535 个文件或 4GB 正文，
        // 与其猜着解析不如老实放弃——解错了会喂给用户一堆乱码
        guard count != 0xFFFF, directoryOffset != 0xFFFF_FFFF,
              directoryOffset >= 0, directoryOffset < bytes.count else { return [] }

        var out: [Entry] = []
        var cursor = directoryOffset
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, u32(bytes, cursor) == centralSignature else { break }
            let nameLength = Int(u16(bytes, cursor + 28))
            let extraLength = Int(u16(bytes, cursor + 30))
            let commentLength = Int(u16(bytes, cursor + 32))
            let nameEnd = cursor + 46 + nameLength
            guard nameEnd <= bytes.count else { break }
            let name = String(decoding: bytes[(cursor + 46)..<nameEnd], as: UTF8.self)
            out.append(Entry(name: name,
                             method: u16(bytes, cursor + 10),
                             compressedSize: Int(u32(bytes, cursor + 20)),
                             uncompressedSize: Int(u32(bytes, cursor + 24)),
                             localHeaderOffset: Int(u32(bytes, cursor + 42))))
            cursor = nameEnd + extraLength + commentLength
        }
        return out
    }

    static func extract(_ entry: Entry, from bytes: [UInt8]) -> Data? {
        let header = entry.localHeaderOffset
        guard header >= 0, header + 30 <= bytes.count,
              u32(bytes, header) == localSignature else { return nil }
        // 本地头的 name/extra 长度可以跟中央目录里的**不一样**（extra 尤其常见），
        // 所以数据起点必须按本地头自己的长度算
        let nameLength = Int(u16(bytes, header + 26))
        let extraLength = Int(u16(bytes, header + 28))
        let start = header + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count, start <= end else { return nil }
        let payload = Array(bytes[start..<end])

        switch entry.method {
        case 0:
            return Data(payload)
        case 8:
            return inflate(payload, expected: entry.uncompressedSize)
        default:
            return nil
        }
    }

    /// 裸 DEFLATE。Apple 的 `COMPRESSION_ZLIB` 指的就是 RFC 1951 裸流
    /// （不带 zlib 头），正好是 ZIP 里存的东西
    private static func inflate(_ payload: [UInt8], expected: Int) -> Data? {
        guard !payload.isEmpty, expected > 0 else { return nil }
        var destination = [UInt8](repeating: 0, count: expected)
        let written = destination.withUnsafeMutableBufferPointer { output -> Int in
            payload.withUnsafeBufferPointer { input -> Int in
                guard let outBase = output.baseAddress, let inBase = input.baseAddress else { return 0 }
                return compression_decode_buffer(outBase, output.count,
                                                 inBase, input.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return Data(destination[0..<written])
    }

    /// 从尾巴往前找中央目录结束记录。注释最长 65535 字节，
    /// 所以最多往回翻 65557 字节就够了
    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowest = max(0, bytes.count - 65_557)
        var index = bytes.count - 22
        while index >= lowest {
            if u32(bytes, index) == eocdSignature { return index }
            index -= 1
        }
        return nil
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }
}
