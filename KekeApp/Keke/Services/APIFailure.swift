import Foundation

/// 一次 API 调用失败的分类结果。
///
/// 在此之前所有非 200 都被抹成 `AIError.badResponse("HTTP 429")`——
/// 上层既分不清「等一下会好」和「配置错了永远不会好」，也就没法退避重试。
/// 判定逻辑集中在这一个类型里，三个请求出口（非流式 Claude / 非流式 OpenAI / 流式）共用。
struct APIFailure: Error, LocalizedError {

    enum Kind: Equatable {
        case badRequest        // 400，请求本身不对
        case auth              // 401，Key 不对
        case permission        // 403，Key 没这个权限 / 没开通这个模型
        case notFound          // 404，模型 id 拼错或接口地址不对
        case tooLarge          // 413，请求体过大
        case rateLimited       // 429
        case overloaded        // 529，Anthropic 侧过载
        case serverError       // 其余 5xx
        case network           // 连不上、断网、连接被掐
        case timeout           // 超时
        case other             // 兜底：认不出来的状态码

        /// 只有「等一会儿可能就好了」的才重试。
        /// 配置类错误（Key、模型 id、请求格式）重试多少次都是一样的结果，
        /// 白等还让用户以为在生成
        var isRetryable: Bool {
            switch self {
            case .rateLimited, .overloaded, .serverError, .network, .timeout:
                return true
            case .badRequest, .auth, .permission, .notFound, .tooLarge, .other:
                return false
            }
        }
    }

    let kind: Kind
    /// HTTP 状态码；连接层面的失败没有状态码
    let status: Int?
    /// 服务端 JSON 里的 `error.type`，比如 `"overloaded_error"`、`"rate_limit_error"`
    let apiType: String?
    /// 服务端原文。**不做加工**——`ContextCompressor.isContextLengthError` 要靠它认超长
    let message: String
    /// `Retry-After` 头解析出来的秒数
    let retryAfter: TimeInterval?
    /// 提供方显示名，用在报错文案里
    let provider: String
    /// 失败之前是不是已经往界面上推过字了。
    /// 流式请求推过字之后就不能重试了——重来一遍界面上的字会倒退再重放
    var emittedOutput: Bool = false

    // MARK: - 构造

    /// 从 HTTP 响应分类。`headers` 单独传是为了让纯逻辑部分可以脱离 URLSession 测
    static func from(status: Int,
                     apiType: String?,
                     message: String,
                     retryAfterHeader: String?,
                     provider: String) -> APIFailure {
        let kind: Kind
        switch status {
        case 400: kind = .badRequest
        case 401: kind = .auth
        case 403: kind = .permission
        case 404: kind = .notFound
        case 408: kind = .timeout
        case 413: kind = .tooLarge
        case 429: kind = .rateLimited
        case 529: kind = .overloaded
        case 500...599: kind = .serverError
        default: kind = .other
        }
        // 有的网关状态码给 500 但 body 里写着 overloaded_error，以 body 为准更准
        let resolved: Kind = (apiType == "overloaded_error" && kind == .serverError) ? .overloaded : kind
        return APIFailure(kind: resolved, status: status, apiType: apiType,
                          message: message, retryAfter: parseRetryAfter(retryAfterHeader),
                          provider: provider)
    }

    /// 从 URLSession 抛出来的错误分类。
    /// 返回 nil 表示「这不是网络失败，别当 API 错误处理」——比如用户主动取消
    static func from(transport error: Error, provider: String) -> APIFailure? {
        if error is CancellationError { return nil }
        guard let urlError = error as? URLError else { return nil }
        let kind: Kind
        switch urlError.code {
        case .cancelled:
            // 用户自己按的停止，不是失败
            return nil
        case .timedOut:
            kind = .timeout
        default:
            // 断网、DNS 挂了、连接被掐、TLS 失败……对用户来说都是"连不上"，
            // 退避重试的处理方式也一样，不用再往下分
            kind = .network
        }
        return APIFailure(kind: kind, status: nil, apiType: nil,
                          message: urlError.localizedDescription,
                          retryAfter: nil, provider: provider)
    }

    /// 流中途报的错只带 `error.type`，没有 HTTP 状态码——请求早就 200 了。
    /// 按类型反查一个等价状态码，后面的分类和重试判断就能和 HTTP 那条路共用一套。
    ///
    /// 认不出来的类型按 500 处理（可重试）：能走到「流中途」说明请求本身已经被接受，
    /// 这时候出的错基本都是服务端侧的
    static func statusForAPIType(_ apiType: String?) -> Int {
        switch apiType {
        case "invalid_request_error": return 400
        case "authentication_error": return 401
        case "permission_error", "insufficient_quota": return 403
        case "not_found_error": return 404
        case "request_too_large": return 413
        case "rate_limit_error", "rate_limit_exceeded": return 429
        case "overloaded_error": return 529
        default: return 500
        }
    }

    /// `Retry-After` 有两种合法写法：秒数（`"30"`）和 HTTP 日期
    /// （`"Wed, 21 Oct 2026 07:28:00 GMT"`）。两种都认，认不出来返回 nil
    static func parseRetryAfter(_ raw: String?) -> TimeInterval? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) {
            return seconds >= 0 ? seconds : nil
        }
        guard let date = httpDateFormatter.date(from: raw) else { return nil }
        let seconds = date.timeIntervalSinceNow
        return seconds > 0 ? seconds : 0
    }

    private static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    // MARK: - 文案

    /// 给用户看的。原则是**说清楚下一步该干什么**，
    /// 只有在用户自己能改的时候才把服务端原文附上（配置类错误），
    /// 服务端自己的毛病（限流、过载、5xx）附原文只会让人更迷惑
    var errorDescription: String? {
        switch kind {
        case .auth:
            return "\(provider) 的 API Key 好像不对，去「设置」里检查一下"
        case .permission:
            return "这个 Key 没有访问该模型的权限，可能是没开通或者额度用完了\(detailSuffix)"
        case .notFound:
            return "找不到这个模型，检查一下设置里的模型名\(detailSuffix)"
        case .tooLarge:
            return "这次要发的内容太大了，删掉点图片或文件再试"
        case .rateLimited:
            return "请求太频繁，被限流了。\(waitHint)"
        case .overloaded:
            return "\(provider) 现在过载了，缓一会儿再发"
        case .serverError:
            return "\(provider) 服务端出错了（HTTP \(status.map(String.init) ?? "5xx")），过一会儿再试"
        case .network:
            return "连不上网络，检查一下网络连接"
        case .timeout:
            return "等太久了没响应，再发一次试试"
        case .badRequest, .other:
            return message.isEmpty ? "请求失败（HTTP \(status.map(String.init) ?? "?")）" : message
        }
    }

    private var detailSuffix: String {
        message.isEmpty ? "" : "：\(message)"
    }

    private var waitHint: String {
        guard let retryAfter, retryAfter > 0 else { return "等一会儿再发" }
        return "大约 \(Int(retryAfter.rounded(.up))) 秒后再发"
    }
}

/// 退避重试的参数。
///
/// 用**全抖动**（`random(0, cap)`）而不是固定的 1s/2s/4s：
/// 限流往往是多个请求同时撞上来的，固定间隔会让它们退避完又同时重来，再撞一次
struct RetryPolicy {
    /// 总共尝试几次（含第一次）。3 = 首次 + 2 次重试
    var maxAttempts: Int = 3
    var baseDelay: TimeInterval = 1
    var maxDelay: TimeInterval = 8
    /// 服务端要求等待超过这个秒数就不重试了——
    /// 与其让界面转圈转一分钟，不如直接告诉用户要等多久
    var retryAfterCeiling: TimeInterval = 20

    static let `default` = RetryPolicy()

    /// `attempt` 从 0 开始数（0 = 第一次失败之后的那次等待）
    func delay(attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            // 服务端明确说了等多久就听它的，别自作聪明退避得更短再撞一次
            return min(retryAfter, retryAfterCeiling)
        }
        let cap = min(maxDelay, baseDelay * pow(2, Double(attempt)))
        return Double.random(in: 0...cap)
    }

    /// 服务端要求的等待时间超出上限时，重试没意义，直接把错误抛给用户
    func allowsRetry(_ failure: APIFailure) -> Bool {
        guard failure.kind.isRetryable else { return false }
        // 已经往界面上推过字了就不能重来，见 APIFailure.emittedOutput
        guard !failure.emittedOutput else { return false }
        if let retryAfter = failure.retryAfter, retryAfter > retryAfterCeiling { return false }
        return true
    }
}

enum APIRetry {

    /// 按策略重试 `operation`。
    ///
    /// - 只有 `APIFailure` 且 `policy.allowsRetry` 为真才重试；
    ///   其它错误（包括 `CancellationError`、解析失败）原样抛出，一次都不重试
    /// - 每次重试前 `Task.sleep`，取消会在这里立刻生效
    static func run<T>(policy: RetryPolicy = .default,
                       provider: String,
                       operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                // 网络层的失败 URLSession 抛的是 URLError，先归一成 APIFailure；
                // 归不了的（取消、解析失败）原样抛，一次都不重试
                let failure: APIFailure
                if let known = error as? APIFailure {
                    failure = known
                } else if let converted = APIFailure.from(transport: error, provider: provider) {
                    failure = converted
                } else {
                    throw error
                }
                guard attempt + 1 < policy.maxAttempts, policy.allowsRetry(failure) else { throw failure }
                let wait = policy.delay(attempt: attempt, retryAfter: failure.retryAfter)
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                attempt += 1
            }
        }
    }
}
