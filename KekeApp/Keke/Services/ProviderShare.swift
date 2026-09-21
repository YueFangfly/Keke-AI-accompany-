import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// 换手机时把自定义供应商的配置搬过去。
///
/// 备份文件是**刻意不含 Key 的**（见 `BackupService.secretKeyMarkers`），
/// 所以搬完家还得手输一遍 Key。二维码补的就是这一环：
/// 面对面扫一下，Key 不落盘、不上传、不进备份。
///
/// 但也正因为如此——**带 Key 的二维码等于明文的 Key**。所以带不带 Key 是
/// 一个默认关闭的开关，界面上必须说清楚这张码不能截图外发。
enum ProviderShare {

    /// 载荷前缀。带版本号，将来改结构时老版本能认出「这码我读不了」，
    /// 而不是解出一半乱七八糟的配置
    static let prefix = "keke-provider:1:"

    /// 二维码在纠错等级 L 下大约能塞 2953 字节。留点余量
    static let maxPayloadBytes = 2600

    struct Payload: Equatable {
        var name: String
        var baseURL: String
        var defaultModel: String
        var keyPlaceholder: String
        var supportsVision: Bool
        var supportsFunctionCalling: Bool
        var headerNames: [String]
        var extraBodyJSON: String
        /// 空 = 这张码不带 Key
        var apiKey: String
        /// 额外请求头的值。同样是密钥性质，跟 apiKey 一起给或一起不给
        var headerValues: [String: String]

        var carriesSecret: Bool { !apiKey.isEmpty || !headerValues.isEmpty }
    }

    // MARK: - 编解码

    enum ShareError: LocalizedError {
        case tooLarge(Int)
        case notAKekeCode
        case brokenPayload

        var errorDescription: String? {
            switch self {
            case .tooLarge(let n):
                return "配置太长了（\(n) 字节），二维码放不下。可以先把「额外 body」精简一下"
            case .notAKekeCode:
                return "这不是克克的配置码"
            case .brokenPayload:
                return "码读出来了，但内容是坏的——可能扫到了一半，或者对面版本太新"
            }
        }
    }

    static func encode(_ payload: Payload) throws -> String {
        var object: [String: Any] = [
            "v": 1,
            "name": payload.name,
            "url": payload.baseURL,
            "model": payload.defaultModel,
            "ph": payload.keyPlaceholder,
            "vision": payload.supportsVision,
            "tools": payload.supportsFunctionCalling,
        ]
        if !payload.headerNames.isEmpty { object["headerNames"] = payload.headerNames }
        if !payload.extraBodyJSON.isEmpty { object["extraBody"] = payload.extraBodyJSON }
        if !payload.apiKey.isEmpty { object["key"] = payload.apiKey }
        if !payload.headerValues.isEmpty { object["headers"] = payload.headerValues }

        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys])
        let body = base64URL(data)
        guard body.utf8.count <= maxPayloadBytes else {
            throw ShareError.tooLarge(body.utf8.count)
        }
        return prefix + body
    }

    static func decode(_ text: String) throws -> Payload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { throw ShareError.notAKekeCode }
        let body = String(trimmed.dropFirst(prefix.count))
        guard let data = dataFromBase64URL(body),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let url = object["url"] as? String,
              !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ShareError.brokenPayload }

        let name = (object["name"] as? String) ?? ""
        return Payload(
            name: name.isEmpty ? "扫码导入的 API" : name,
            baseURL: url,
            defaultModel: (object["model"] as? String) ?? "",
            keyPlaceholder: (object["ph"] as? String) ?? "sk-…",
            supportsVision: (object["vision"] as? Bool) ?? false,
            supportsFunctionCalling: (object["tools"] as? Bool) ?? true,
            headerNames: (object["headerNames"] as? [String]) ?? [],
            extraBodyJSON: (object["extraBody"] as? String) ?? "",
            apiKey: (object["key"] as? String) ?? "",
            headerValues: (object["headers"] as? [String: String]) ?? [:]
        )
    }

    /// base64url：标准 base64 换掉 `+/`、去掉 `=`。
    /// 二维码本身不挑字符，但这串会被复制粘贴、被塞进链接，规规矩矩点省事
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func dataFromBase64URL(_ text: String) -> Data? {
        var s = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: s)
    }

    // MARK: - 画码

    /// 生成二维码。纠错等级用 M：屏幕上扫，不需要 H 那么强的抗污损，
    /// 换来的是同样尺寸下能塞更多内容
    static func qrImage(_ text: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
