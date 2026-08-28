import SwiftUI

/// 探索页 → 克克读代码：绑定一次只读 token，克克就能浏览你 GitHub 仓库里的文件，
/// 你点开哪个她读哪个、给你修改建议（只读不改）
struct CodeReviewView: View {
    @EnvironmentObject var store: ChatStore
    @StateObject private var gh = GitHubReaderService()

    /// 当前所在目录链（每一项是一层目录的完整 path，空数组 = 仓库根）
    @State private var pathStack: [String] = []
    @State private var entries: [GitHubReaderService.Entry] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var openFile: OpenFile?
    @State private var showSetup = false

    struct OpenFile: Identifiable {
        let id = UUID()
        let name: String
        let content: String
    }

    private var lang: AppLanguage { store.appLanguage }
    private var currentPath: String { pathStack.last ?? "" }

    var body: some View {
        Group {
            if gh.configured {
                browser
            } else {
                SetupView(gh: gh) { reload() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .sheet(item: $openFile) { file in
            CodeFileView(fileName: file.name, code: file.content)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSetup) {
            NavigationView {
                SetupView(gh: gh) {
                    showSetup = false
                    reload()
                }
                .navigationTitle(L.t("绑定仓库", lang))
                .navigationBarTitleDisplayMode(.inline)
            }
            .environmentObject(store)
        }
    }

    // MARK: - 浏览

    private var browser: some View {
        VStack(spacing: 0) {
            header
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                errorState(errorText)
            } else {
                List {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task(id: pathStack) { await loadNow() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !pathStack.isEmpty {
                Button {
                    pathStack.removeLast()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(gh.owner)/\(gh.repo)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(currentPath.isEmpty ? L.t("根目录", lang) : currentPath)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                showSetup = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.card)
    }

    private func entryRow(_ entry: GitHubReaderService.Entry) -> some View {
        Button {
            if entry.isDir {
                pathStack.append(entry.path)
            } else {
                openFileAt(entry)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.isDir ? "folder.fill" : "doc.text")
                    .font(.system(size: 15))
                    .foregroundStyle(entry.isDir ? Theme.accent : Theme.textSecondary)
                    .frame(width: 22)
                Text(entry.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if entry.isDir {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.background)
    }

    private func errorState(_ text: String) -> some View {
        VStack(spacing: 12) {
            Text("🐱")
                .font(.system(size: 40))
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 30)
            Button(L.t("重新绑定", lang)) { showSetup = true }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() {
        pathStack = []
        Task { await loadNow() }
    }

    private func loadNow() async {
        guard gh.configured else { return }
        loading = true
        errorText = nil
        do {
            entries = try await gh.listDir(currentPath)
        } catch {
            entries = []
            errorText = error.localizedDescription
        }
        loading = false
    }

    private func openFileAt(_ entry: GitHubReaderService.Entry) {
        loading = true
        Task {
            do {
                let content = try await gh.fetchFile(entry.path)
                openFile = OpenFile(name: entry.name, content: content)
            } catch {
                errorText = error.localizedDescription
            }
            loading = false
        }
    }
}

// MARK: - 绑定仓库（填 token）

private struct SetupView: View {
    @EnvironmentObject var store: ChatStore
    @ObservedObject var gh: GitHubReaderService
    let onSaved: () -> Void

    @State private var draftToken = ""
    @State private var draftOwner = ""
    @State private var draftRepo = ""
    @State private var draftBranch = ""

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("🔑 " + String(format: L.t("让%@能读你的代码", lang), personaName))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)

                Text(String(format: L.t("你的仓库是私有的，%@要读它得有一把「只读钥匙」。放心，这把钥匙只能看、不能改。", lang), personaName))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    field(L.t("只读钥匙（token）", lang), text: $draftToken, secure: true,
                          placeholder: "github_pat_…")
                    field(L.t("仓库拥有者", lang), text: $draftOwner, placeholder: "YueFangfly")
                    field(L.t("仓库名", lang), text: $draftRepo, placeholder: "LoveClaude")
                    field(L.t("分支（留空=默认分支）", lang), text: $draftBranch,
                          placeholder: "claude/elevenlabs-phone-calls-8xbt9o")
                }

                Button {
                    gh.token = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    gh.owner = draftOwner.trimmingCharacters(in: .whitespacesAndNewlines)
                    gh.repo = draftRepo.trimmingCharacters(in: .whitespacesAndNewlines)
                    gh.branch = draftBranch.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSaved()
                } label: {
                    Text(L.t("保存", lang))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
                }
                .disabled(draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                howToCard
            }
            .padding(16)
        }
        .onAppear {
            draftToken = gh.token
            draftOwner = gh.owner
            draftRepo = gh.repo
            draftBranch = gh.branch
        }
    }

    private func field(_ label: String, text: Binding<String>, secure: Bool = false,
                       placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        }
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("怎么弄这把只读钥匙", lang))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(L.t("在电脑或手机浏览器打开 github.com → 右上角头像 → Settings → 最下面 Developer settings → Personal access tokens → Fine-grained tokens → Generate new token。Repository access 选你的 LoveClaude；Permissions 里把 Contents 设成 Read-only 就够了。生成后把那串 github_pat_… 复制粘贴到上面。", lang))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12)
    }
}

// MARK: - 看一个文件 + 问克克

private struct CodeFileView: View {
    @EnvironmentObject var store: ChatStore
    let fileName: String
    let code: String
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var advice: String?
    @State private var asking = false

    private var lang: AppLanguage { store.appLanguage }
    private var personaName: String { PersonaStore.persona(for: store.personaId).name }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    askCard
                    if asking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(String(format: L.t("%@在看…", lang), personaName))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else if let advice {
                        adviceCard(advice)
                    }
                    codeCard
                }
                .padding(14)
            }
            .background(Theme.background)
            .navigationTitle(fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("关闭", lang)) { dismiss() }
                }
            }
        }
    }

    private var askCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(String(format: L.t("想让%@重点看什么 / 改什么（可留空）", lang), personaName), text: $question, axis: .vertical)
                .lineLimit(1...3)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
            Button {
                ask()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(String(format: L.t("让%@看看", lang), personaName))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
            }
            .disabled(asking || store.apiKey.isEmpty)
            if store.apiKey.isEmpty {
                Text(String(format: L.t("先在设置里填好 API Key，%@才能看", lang), personaName))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func adviceCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("🐱")
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12)
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("文件内容", lang))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code.isEmpty ? L.t("（读到的内容是空的）", lang) : code)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        }
    }

    private func ask() {
        asking = true
        advice = nil
        Task {
            let result = try? await ClaudeService.codeAdvice(
                fileName: fileName, code: code, question: question,
                userName: store.myName, provider: store.provider, apiKey: store.apiKey,
                model: store.model, systemPrompt: store.effectiveSystemPrompt)
            advice = result ?? String(format: L.t("%@没看成，检查下网络或 API Key", lang), personaName)
            asking = false
        }
    }
}
