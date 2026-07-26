import UIKit
import PDFKit
import Vision

/// 聊天附件：图片保存/读取，文档（pdf/txt/html/md）文字提取
enum Attachments {

    static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// 保存图片（压到长边 1400 以内的 JPEG），返回文件名
    static func saveImage(_ image: UIImage) -> String? {
        let resized = downscale(image, maxSide: 1400)
        guard let data = resized.jpegData(compressionQuality: 0.7) else { return nil }
        let name = "img_\(UUID().uuidString).jpg"
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func loadImage(named name: String) -> UIImage? {
        UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    static func base64JPEG(named name: String) -> String? {
        (try? Data(contentsOf: dir.appendingPathComponent(name)))?.base64EncodedString()
    }

    private static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    /// 提取文档文字（pdf / txt / html / md），最多 30000 字——给聊天附件用，
    /// 要发给 AI 当上下文，不能太长
    static func extractText(from url: URL) -> String? {
        guard var result = rawText(from: url, pdfPageLimit: 80) else { return nil }
        if result.count > 30_000 {
            result = String(result.prefix(30_000)) + "\n（后面太长，截断了）"
        }
        return result
    }

    /// 提取整本书的文字（pdf / txt / html / md），给「阅读」功能用，
    /// 上限放宽很多（300 页 / 300 万字），但还是留一个安全上限防止内存爆掉
    static func extractBookText(from url: URL) -> String? {
        guard var result = rawText(from: url, pdfPageLimit: 300) else { return nil }
        if result.count > 3_000_000 {
            result = String(result.prefix(3_000_000)) + "\n（后面太长，截断了）"
        }
        return result
    }

    private static func rawText(from url: URL, pdfPageLimit: Int) -> String? {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        var text: String?
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let doc = PDFDocument(url: url) else { return nil }
            var out = ""
            for index in 0..<min(doc.pageCount, pdfPageLimit) {
                out += doc.page(at: index)?.string ?? ""
                out += "\n"
            }
            text = out
        case "html", "htm":
            text = readString(url)?
                .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ",
                                      options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ",
                                      options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        default:
            text = readString(url)
        }

        let result = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result, !result.isEmpty else { return nil }
        return result
    }

    /// 抓一个网页的正文文字——给非 Claude 家的"读网页"工具用（Claude 走的是官方 web_fetch，
    /// 更强，不需要这个）。只做直接抓取，不是搜索引擎，得给一个具体的网址
    static func fetchWebpageText(urlString: String) async throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) KekeApp/1.0",
                         forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw URLError(.cannotDecodeContentData)
        }

        var text = raw
            .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw URLError(.zeroByteResource) }
        if text.count > 15_000 {
            text = String(text.prefix(15_000)) + "\n（后面太长，截断了）"
        }
        return text
    }

    /// 本地识图，完全免费——给不支持看图的模型（比如 DeepSeek）一点点关于图片内容的线索：
    /// 大致的场景/物体标签 + 图片里的文字（Vision 框架自带的，不调用任何 AI）。
    /// 不如真的 AI 识图准，但不花一分钱
    static func describeImageLocally(_ image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let classifyRequest = VNClassifyImageRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast

        do {
            try handler.perform([classifyRequest, textRequest])
        } catch {
            return nil
        }

        let labels = (classifyRequest.results ?? [])
            .filter { $0.confidence > 0.3 }
            .prefix(5)
            .map { $0.identifier }
        let lines = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .prefix(10)

        var parts: [String] = []
        if !labels.isEmpty { parts.append("可能包含：" + labels.joined(separator: "、")) }
        if !lines.isEmpty { parts.append("图片里的文字：" + lines.joined(separator: " / ")) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "；")
    }

    /// 先按 UTF-8 读，失败再按 GB18030（很多中文 txt 是这个编码）
    private static func readString(_ url: URL) -> String? {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        let gbk = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let data = try? Data(contentsOf: url),
           let s = String(data: data, encoding: String.Encoding(rawValue: gbk)) {
            return s
        }
        return nil
    }
}
