import Foundation

/// 让克克「只读」地看你 GitHub 仓库里的代码：存一把只读 token，
/// 按目录浏览、读取单个文件的正文。只读不写——拿到的 token 权限也只给「读」，
/// 就算泄漏也改不了你的东西
@MainActor
final class GitHubReaderService: ObservableObject {
    @Published var token: String { didSet { defaults.set(token, forKey: "gh_token") } }
    @Published var owner: String { didSet { defaults.set(owner, forKey: "gh_owner") } }
    @Published var repo: String { didSet { defaults.set(repo, forKey: "gh_repo") } }
    /// 看哪个分支；留空就是仓库默认分支
    @Published var branch: String { didSet { defaults.set(branch, forKey: "gh_branch") } }

    private let defaults = UserDefaults.standard

    init() {
        token = defaults.string(forKey: "gh_token") ?? ""
        owner = defaults.string(forKey: "gh_owner") ?? "YueFangfly"
        repo = defaults.string(forKey: "gh_repo") ?? "LoveClaude"
        branch = defaults.string(forKey: "gh_branch") ?? ""
    }

    var configured: Bool {
        !token.isEmpty
            && !owner.trimmingCharacters(in: .whitespaces).isEmpty
            && !repo.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 仓库里的一项：文件或文件夹
    struct Entry: Identifiable, Hashable {
        let name: String
        let path: String
        let isDir: Bool
        var id: String { path }
    }

    private struct ContentItem: Decodable {
        let name: String
        let path: String
        let type: String
        let content: String?
        let encoding: String?
        let download_url: String?
    }

    // MARK: - 请求

    private func makeRequest(path: String) throws -> URLRequest {
        let encodedPath = path.split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        // 根目录不要带结尾斜杠
        var urlString = "https://api.github.com/repos/\(owner)/\(repo)/contents"
        if !encodedPath.isEmpty { urlString += "/\(encodedPath)" }
        let trimmedBranch = branch.trimmingCharacters(in: .whitespaces)
        if !trimmedBranch.isEmpty,
           let ref = trimmedBranch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "?ref=\(ref)"
        }
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Moonlight-App", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["message"] as? String
            throw NSError(domain: "GitHub", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: message ?? "HTTP \(http.statusCode)"])
        }
    }

    /// 列出某个目录（path 为空就是仓库根目录）：文件夹排前面，其余按名字
    func listDir(_ path: String) async throws -> [Entry] {
        let (data, response) = try await URLSession.shared.data(for: try makeRequest(path: path))
        try Self.check(response, data)
        let items = try JSONDecoder().decode([ContentItem].self, from: data)
        return items
            .map { Entry(name: $0.name, path: $0.path, isDir: $0.type == "dir") }
            .sorted { lhs, rhs in
                if lhs.isDir != rhs.isDir { return lhs.isDir }
                return lhs.name.lowercased() < rhs.name.lowercased()
            }
    }

    /// 读取单个文件的正文
    func fetchFile(_ path: String) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: try makeRequest(path: path))
        try Self.check(response, data)
        let item = try JSONDecoder().decode(ContentItem.self, from: data)
        if let content = item.content, item.encoding == "base64",
           let decoded = Data(base64Encoded: content, options: .ignoreUnknownCharacters),
           let text = String(data: decoded, encoding: .utf8) {
            return text
        }
        // 太大的文件 contents 接口不直接给正文，走 download_url 再拿一次
        if let urlString = item.download_url, let url = URL(string: urlString) {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("Moonlight-App", forHTTPHeaderField: "User-Agent")
            let (fileData, fileResponse) = try await URLSession.shared.data(for: request)
            try Self.check(fileResponse, fileData)
            return String(data: fileData, encoding: .utf8) ?? ""
        }
        return ""
    }
}
