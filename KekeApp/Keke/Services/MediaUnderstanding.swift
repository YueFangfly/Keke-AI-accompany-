import Foundation
import ImageIO
import UIKit
import Vision

/// 媒体理解：把一张图 / 一段话里能白拿的信息先抠出来。
///
/// **必须排在卡片生成前面**——后面要把碎片整理成卡片时，读的是这里的结果。
/// 顺序反了，卡片就只能看着一个文件名瞎猜。
///
/// 全部本地：EXIF 走 ImageIO，标签和文字走 Vision。不上传、不花钱。
enum MediaUnderstanding {

    // MARK: - 对外

    /// 分析一张照片。
    ///
    /// `original` 是**没被处理过的**原始文件数据。这个参数不能省：
    /// `Attachments.saveImage` 会重新编码成 JPEG，EXIF 在那一步就没了，
    /// 所以拍摄时间和 GPS 必须在保存之前从原始数据里读出来。
    static func analyzePhoto(original: Data?, image: UIImage) async -> MediaAnalysis {
        var analysis = MediaAnalysis()

        if let original {
            let meta = exifMetadata(original)
            analysis.capturedAt = meta.capturedAt
            analysis.latitude = meta.latitude
            analysis.longitude = meta.longitude
        }

        do {
            let seen = try vision(image)
            analysis.labels = seen.labels
            analysis.ocr = seen.ocr
        } catch {
            analysis.failure = error.localizedDescription
        }
        analysis.analyzedAt = Date()
        return analysis
    }

    // MARK: - EXIF

    struct PhotoMetadata: Equatable {
        var capturedAt: Date?
        var latitude: Double?
        var longitude: Double?
    }

    static func exifMetadata(_ data: Data) -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return PhotoMetadata() }

        var out = PhotoMetadata()

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
            out.capturedAt = parseEXIFDate(stamp, offset: offset)
        }

        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            let lat = signed(gps[kCGImagePropertyGPSLatitude] as? Double,
                             ref: gps[kCGImagePropertyGPSLatitudeRef] as? String,
                             negativeRef: "S", limit: 90)
            let lon = signed(gps[kCGImagePropertyGPSLongitude] as? Double,
                             ref: gps[kCGImagePropertyGPSLongitudeRef] as? String,
                             negativeRef: "W", limit: 180)
            // (0, 0) 是几内亚湾里的一个点，现实中不会有人在那儿拍照——
            // 它几乎总是「相机写了个占位值」。当没有处理
            if let lat, let lon, !(lat == 0 && lon == 0) {
                out.latitude = lat
                out.longitude = lon
            }
        }
        return out
    }

    /// EXIF 的时间戳长这样：`2026:09:03 14:22:07`，**冒号分隔日期**，而且不带时区。
    ///
    /// 新一点的文件会另外给一个 `OffsetTimeOriginal`（`+08:00`）。有就用，
    /// 没有就当本地时间——这是唯一合理的猜法：照片上的时间本来就是拍的时候当地的钟。
    static func parseEXIFDate(_ raw: String?, offset: String?) -> Date? {
        guard let raw else { return nil }
        let stamp = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stamp.count == 19 else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = timeZone(offset) ?? TimeZone.current

        guard let date = formatter.date(from: stamp) else { return nil }
        // 1990 年之前的数码照片基本不存在；未来的时间更是坏数据。
        // 让一个坏 EXIF 把碎片扔到 1904 年去，比读不到时间糟糕得多
        guard date > Date(timeIntervalSince1970: 631_152_000),
              date < Date().addingTimeInterval(86_400) else { return nil }
        return date
    }

    /// `+08:00` / `-05:30` / `+0800` / `Z` 都认
    static func timeZone(_ offset: String?) -> TimeZone? {
        guard var text = offset?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        if text == "Z" || text == "z" { return TimeZone(secondsFromGMT: 0) }

        let sign: Int
        switch text.first {
        case "+": sign = 1
        case "-": sign = -1
        default: return nil
        }
        text.removeFirst()
        text = text.replacingOccurrences(of: ":", with: "")
        guard text.count == 4, let value = Int(text) else { return nil }
        let hours = value / 100, minutes = value % 100
        guard hours <= 14, minutes < 60 else { return nil }
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }

    /// EXIF 的经纬度**永远是正数**，方向单独放在 Ref 字段里（N/S、E/W）。
    /// 忘了带符号，南半球和西半球的照片会全部落到地球另一边
    static func signed(_ value: Double?, ref: String?, negativeRef: String, limit: Double) -> Double? {
        guard let value, value.isFinite, abs(value) <= limit else { return nil }
        let direction = (ref ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return direction == negativeRef ? -abs(value) : abs(value)
    }

    // MARK: - Vision

    struct VisionResult: Equatable {
        var labels: [String] = []
        var ocr: String = ""
    }

    enum VisionFailure: LocalizedError {
        case noBitmap
        var errorDescription: String? { "这张图读不出像素，可能是坏文件" }
    }

    /// 场景标签 + 图里的文字。跟 `Attachments.describeImageLocally` 是同一套框架，
    /// 但这里要的是**结构化字段**（标签和文字分开存），不是拼给模型看的一句话
    static func vision(_ image: UIImage) throws -> VisionResult {
        guard let cgImage = image.cgImage else { throw VisionFailure.noBitmap }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let classify = VNClassifyImageRequest()
        let recognize = VNRecognizeTextRequest()
        recognize.recognitionLevel = .accurate
        recognize.recognitionLanguages = ["zh-Hans", "en-US"]
        recognize.usesLanguageCorrection = true

        try handler.perform([classify, recognize])

        var result = VisionResult()
        result.labels = (classify.results ?? [])
            .filter { $0.confidence > 0.3 }
            .prefix(5)
            .map { $0.identifier }
        let lines = (recognize.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .prefix(20)
        result.ocr = lines.joined(separator: "\n")
        return result
    }
}
