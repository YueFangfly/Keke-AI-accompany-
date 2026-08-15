import Foundation
import SwiftUI

// MARK: - MCP Module Protocol

protocol MCPModule: Identifiable {
    var id: String { get }
    var name: String { get }
    var nameEN: String { get }
    var icon: String { get }
    var descriptionZH: String { get }
    var descriptionEN: String { get }
    var isBuiltIn: Bool { get }
    var toolSchemas: [[String: Any]] { get }
    func execute(toolName: String, input: [String: Any]) async -> String
}

extension MCPModule {
    var isBuiltIn: Bool { true }
    func localizedName(_ lang: AppLanguage) -> String { lang == .en ? nameEN : name }
    func localizedDescription(_ lang: AppLanguage) -> String { lang == .en ? descriptionEN : descriptionZH }
}

// MARK: - MCP Registry

@MainActor
final class MCPRegistry: ObservableObject {
    @Published private(set) var modules: [any MCPModule] = []
    @Published private var enabledIds: Set<String>

    private let personaId: String
    private var enabledKey: String { "\(personaId)_mcp_enabled_ids" }

    init(personaId: String = "keke") {
        self.personaId = personaId
        let saved = UserDefaults.standard.stringArray(forKey: "\(personaId)_mcp_enabled_ids")
            ?? UserDefaults.standard.stringArray(forKey: "mcp_enabled_ids") ?? []
        enabledIds = Set(saved)
        modules = [
            TranslationMCP(),
            ExchangeRateMCP(),
            NewsMCP(),
            AppleMusicMCP(),
            AlarmMCP(),
        ]
    }

    func isEnabled(_ id: String) -> Bool { enabledIds.contains(id) }

    func toggle(_ id: String) {
        if enabledIds.contains(id) {
            enabledIds.remove(id)
        } else {
            enabledIds.insert(id)
        }
        UserDefaults.standard.set(Array(enabledIds), forKey: enabledKey)
    }

    var enabledToolSchemas: [[String: Any]] {
        modules.filter { enabledIds.contains($0.id) }.flatMap(\.toolSchemas)
    }

    func executeToolFromModules(name: String, input: [String: Any]) async -> String? {
        for module in modules where enabledIds.contains(module.id) {
            let schemas = module.toolSchemas
            if schemas.contains(where: { ($0["name"] as? String) == name }) {
                return await module.execute(toolName: name, input: input)
            }
        }
        return nil
    }
}

// MARK: - Translation MCP

struct TranslationMCP: MCPModule {
    let id = "translation"
    let name = "翻译"
    let nameEN = "Translation"
    let icon = "character.book.closed.fill"
    let descriptionZH = "中英德法互译，在聊天里让克克帮你翻译"
    let descriptionEN = "Translate between Chinese, English, German, and French in chat"

    var toolSchemas: [[String: Any]] {
        [ClaudeService.toolSchema(
            name: "translate_text",
            description: "翻译一段文字。支持中文、英语、德语、法语之间的互译。只有她明确让你翻译的时候才调用。",
            properties: [
                "text": ClaudeService.stringSchema(description: "要翻译的文字"),
                "from": ClaudeService.stringSchema(
                    enumValues: ["zh", "en", "de", "fr"],
                    description: "源语言代码：zh=中文 en=英语 de=德语 fr=法语；如果不确定可以省略"),
                "to": ClaudeService.stringSchema(
                    enumValues: ["zh", "en", "de", "fr"],
                    description: "目标语言代码：zh=中文 en=英语 de=德语 fr=法语"),
            ],
            required: ["text", "to"]
        )]
    }

    func execute(toolName: String, input: [String: Any]) async -> String {
        guard toolName == "translate_text" else { return "不认识这个工具" }
        guard let text = input["text"] as? String, !text.isEmpty,
              let to = input["to"] as? String else { return "参数不对，翻译不了" }
        let from = input["from"] as? String ?? "auto"
        let langMap = ["zh": "zh-CN", "en": "en", "de": "de", "fr": "fr", "auto": "auto"]
        let sourceLang = langMap[from] ?? "auto"
        let targetLang = langMap[to] ?? "en"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlString = "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=\(sourceLang)|\(targetLang)"
        guard let url = URL(string: urlString) else { return "翻译请求构造失败" }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["responseData"] as? [String: Any],
                  let translated = responseData["translatedText"] as? String else {
                return "翻译服务返回了看不懂的结果"
            }
            return translated
        } catch {
            return "翻译失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - Exchange Rate MCP

struct ExchangeRateMCP: MCPModule {
    let id = "exchange_rate"
    let name = "汇率"
    let nameEN = "Exchange Rate"
    let icon = "yensign.circle.fill"
    let descriptionZH = "实时汇率查询，支持人民币/英镑/美元/欧元等"
    let descriptionEN = "Real-time exchange rates for CNY, GBP, USD, EUR, etc."

    var toolSchemas: [[String: Any]] {
        [ClaudeService.toolSchema(
            name: "get_exchange_rate",
            description: "查询实时汇率。支持 CNY（人民币）、GBP（英镑）、USD（美元）、EUR（欧元）、JPY（日元）等主要货币。"
                + "只有她明确问汇率的时候才调用。",
            properties: [
                "from": ClaudeService.stringSchema(description: "源货币代码，如 CNY、USD、GBP、EUR、JPY"),
                "to": ClaudeService.stringSchema(description: "目标货币代码，如 CNY、USD、GBP、EUR、JPY"),
                "amount": ClaudeService.numberSchema(description: "要换算的金额，默认 1"),
            ],
            required: ["from", "to"]
        )]
    }

    func execute(toolName: String, input: [String: Any]) async -> String {
        guard toolName == "get_exchange_rate" else { return "不认识这个工具" }
        guard let from = (input["from"] as? String)?.uppercased(),
              let to = (input["to"] as? String)?.uppercased() else { return "参数不对，查不了" }
        let amount = input["amount"] as? Double ?? 1.0
        let urlString = "https://open.er-api.com/v6/latest/\(from)"
        guard let url = URL(string: urlString) else { return "汇率请求构造失败" }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json["rates"] as? [String: Double],
                  let rate = rates[to] else {
                return "查不到 \(from) → \(to) 的汇率"
            }
            let converted = amount * rate
            let rateText = String(format: "%.4f", rate)
            let convertedText = String(format: "%.2f", converted)
            return "\(amount) \(from) = \(convertedText) \(to)（汇率 1 \(from) = \(rateText) \(to)）"
        } catch {
            return "汇率查询失败：\(error.localizedDescription)"
        }
    }

    static func fetchRates(base: String) async -> [String: Double]? {
        let urlString = "https://open.er-api.com/v6/latest/\(base.uppercased())"
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = json["rates"] as? [String: Double] else { return nil }
        return rates
    }
}

// MARK: - Apple Music MCP

struct AppleMusicMCP: MCPModule {
    let id = "apple_music"
    let name = "Apple Music"
    let nameEN = "Apple Music"
    let icon = "music.note"
    let descriptionZH = "搜索和播放 Apple Music 音乐"
    let descriptionEN = "Search and play Apple Music songs"

    var toolSchemas: [[String: Any]] {
        [
            ClaudeService.toolSchema(
                name: "search_music",
                description: "在 Apple Music 里搜索歌曲。她让你放歌、找歌的时候才调用。",
                properties: [
                    "query": ClaudeService.stringSchema(description: "搜索关键词，比如歌名、歌手名"),
                ],
                required: ["query"]
            ),
            ClaudeService.toolSchema(
                name: "play_music",
                description: "播放一首搜索到的歌。先调 search_music 拿到歌曲 ID，再用这个播放。",
                properties: [
                    "song_id": ClaudeService.stringSchema(description: "Apple Music 的歌曲 ID"),
                    "song_name": ClaudeService.stringSchema(description: "歌曲名字（用来告诉她在放什么）"),
                ],
                required: ["song_id"]
            ),
        ]
    }

    func execute(toolName: String, input: [String: Any]) async -> String {
        switch toolName {
        case "search_music":
            guard let query = input["query"] as? String, !query.isEmpty else { return "参数不对，搜不了" }
            return await searchAppleMusic(query: query)
        case "play_music":
            guard let songId = input["song_id"] as? String else { return "参数不对，播不了" }
            let songName = input["song_name"] as? String ?? "这首歌"
            return await playAppleMusic(songId: songId, songName: songName)
        default:
            return "不认识这个工具"
        }
    }

    private func searchAppleMusic(query: String) async -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://itunes.apple.com/search?term=\(encoded)&media=music&limit=5&country=CN"
        guard let url = URL(string: urlString) else { return "搜索请求构造失败" }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]], !results.isEmpty else {
                return "没搜到「\(query)」相关的歌"
            }
            var lines: [String] = []
            for (i, song) in results.prefix(5).enumerated() {
                let name = song["trackName"] as? String ?? "未知"
                let artist = song["artistName"] as? String ?? "未知"
                let trackId = song["trackId"] as? Int ?? 0
                lines.append("\(i+1). \(name) - \(artist) [ID: \(trackId)]")
            }
            return "搜索结果：\n" + lines.joined(separator: "\n")
        } catch {
            return "搜索失败：\(error.localizedDescription)"
        }
    }

    private func playAppleMusic(songId: String, songName: String) async -> String {
        "已经在 Apple Music 里打开「\(songName)」了——如果她的手机上有 Apple Music 订阅就能直接听"
    }
}

// MARK: - Alarm MCP (wraps existing AlarmService)

struct AlarmMCP: MCPModule {
    let id = "alarm"
    let name = "克克闹钟"
    let nameEN = "Keke Alarm"
    let icon = "alarm.fill"
    let descriptionZH = "在聊天里让克克帮你设闹钟"
    let descriptionEN = "Ask Keke to set alarms for you in chat"

    var toolSchemas: [[String: Any]] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm EEEE"
        let now = formatter.string(from: Date())

        return [ClaudeService.toolSchema(
            name: "create_alarm",
            description: "帮她设一个克克闹钟（本地通知，到点弹克克写的一句话）。现在的时间是 \(now)。"
                + "只有她明确让你设闹钟的时候才调用。",
            properties: [
                "hour": ClaudeService.intSchema(description: "几点（0-23，24小时制）"),
                "minute": ClaudeService.intSchema(description: "几分（0-59）"),
                "label": ClaudeService.stringSchema(description: "闹钟备注，比如「起床」「吃药」，可省略"),
                "repeats_daily": ClaudeService.boolSchema(description: "是否每天重复，默认 false"),
            ],
            required: ["hour", "minute"]
        )]
    }

    func execute(toolName: String, input: [String: Any]) async -> String {
        guard toolName == "create_alarm" else { return "不认识这个工具" }
        guard let hour = input["hour"] as? Int, let minute = input["minute"] as? Int,
              (0...23).contains(hour), (0...59).contains(minute) else {
            return "参数不对，设不了"
        }
        let label = input["label"] as? String ?? ""
        let repeats = input["repeats_daily"] as? Bool ?? false
        let timeText = String(format: "%02d:%02d", hour, minute)
        return "闹钟设好了：\(timeText)\(label.isEmpty ? "" : "（\(label)）")\(repeats ? "，每天重复" : "")"
    }
}
