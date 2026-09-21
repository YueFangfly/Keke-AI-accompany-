import Foundation

struct WeatherMCP: MCPModule {
    let id = "weather"
    let name = "天气"
    let nameEN = "Weather"
    let icon = "cloud.sun.fill"
    let descriptionZH = "查询城市的实时天气和未来几天的预报"
    let descriptionEN = "Check current weather and forecasts for any city"

    var toolSchemas: [[String: Any]] {
        [ClaudeService.toolSchema(
            name: "get_weather",
            description: "查询某个城市的天气。她聊到天气、出门穿什么、要不要带伞等场景时可以主动调用。",
            properties: [
                "city": ClaudeService.stringSchema(
                    description: "城市名（中文或英文都行，比如「北京」「London」「东京」）"),
            ],
            required: ["city"]
        )]
    }

    func execute(toolName: String, input: [String: Any]) async -> String {
        guard toolName == "get_weather" else { return "不认识这个工具" }
        guard let city = input["city"] as? String, !city.isEmpty else { return "参数不对，查不了" }
        let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let urlString = "https://wttr.in/\(encoded)?format=j1&lang=zh"
        guard let url = URL(string: urlString) else { return "天气请求构造失败" }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "天气服务返回了看不懂的结果"
            }
            return parseWeather(json, city: city)
        } catch {
            return "天气查询失败：\(error.localizedDescription)"
        }
    }

    private func parseWeather(_ json: [String: Any], city: String) -> String {
        var lines: [String] = []

        if let current = (json["current_condition"] as? [[String: Any]])?.first {
            let tempC = current["temp_C"] as? String ?? "?"
            let feelsLike = current["FeelsLikeC"] as? String ?? "?"
            let humidity = current["humidity"] as? String ?? "?"
            let windSpeed = current["windspeedKmph"] as? String ?? "?"
            let desc = (current["lang_zh"] as? [[String: Any]])?.first?["value"] as? String
                ?? (current["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String
                ?? "未知"
            lines.append("【\(city) 现在的天气】")
            lines.append("\(desc)，气温 \(tempC)°C（体感 \(feelsLike)°C）")
            lines.append("湿度 \(humidity)%，风速 \(windSpeed)km/h")
        }

        if let forecasts = json["weather"] as? [[String: Any]] {
            for (i, day) in forecasts.prefix(3).enumerated() {
                let date = day["date"] as? String ?? "?"
                let maxTemp = day["maxtempC"] as? String ?? "?"
                let minTemp = day["mintempC"] as? String ?? "?"
                let hourly = day["hourly"] as? [[String: Any]]
                let desc = hourly?.first.flatMap {
                    ($0["lang_zh"] as? [[String: Any]])?.first?["value"] as? String
                        ?? ($0["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String
                } ?? ""
                let label = i == 0 ? "今天" : (i == 1 ? "明天" : "后天")
                lines.append("\(label)(\(date))：\(minTemp)~\(maxTemp)°C \(desc)")
            }
        }

        return lines.isEmpty ? "查到了 \(city) 但解析不出天气数据" : lines.joined(separator: "\n")
    }
}
