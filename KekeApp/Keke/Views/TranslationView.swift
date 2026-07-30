import SwiftUI

struct TranslationView: View {
    @EnvironmentObject var store: ChatStore
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var fromLang = "zh"
    @State private var toLang = "en"
    @State private var isLoading = false

    private var lang: AppLanguage { store.appLanguage }

    private let languages: [(code: String, zh: String, en: String)] = [
        ("zh", "中文", "Chinese"),
        ("en", "英语", "English"),
        ("de", "德语", "German"),
        ("fr", "法语", "French"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text(L.t("翻译", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)

            APIPickerBar(moduleId: "translation")

            HStack(spacing: 12) {
                langPicker(selected: $fromLang)
                Button {
                    let temp = fromLang
                    fromLang = toLang
                    toLang = temp
                    let tempText = inputText
                    inputText = outputText
                    outputText = tempText
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(8)
                        .glassCard(cornerRadius: 10)
                }
                langPicker(selected: $toLang)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                TextEditor(text: $inputText)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(height: 100)
                    .padding(10)
                    .glassCard(cornerRadius: 14)

                Button {
                    Task { await translate() }
                } label: {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(L.t("翻译一下", lang))
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)

                if !outputText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(outputText)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                            Spacer()
                        }
                        HStack {
                            Spacer()
                            Button {
                                UIPasteboard.general.string = outputText
                            } label: {
                                Label(L.t("复制", lang), systemImage: "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .padding(10)
                    .glassCard(cornerRadius: 14)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .background(Theme.background)
    }

    private func langPicker(selected: Binding<String>) -> some View {
        Menu {
            ForEach(languages, id: \.code) { l in
                Button(lang == .en ? l.en : l.zh) {
                    selected.wrappedValue = l.code
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(langLabel(selected.wrappedValue))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassCard(cornerRadius: 10)
        }
    }

    private func langLabel(_ code: String) -> String {
        guard let l = languages.first(where: { $0.code == code }) else { return code }
        return lang == .en ? l.en : l.zh
    }

    private func translate() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let langMap = ["zh": "zh-CN", "en": "en", "de": "de", "fr": "fr"]
        let source = langMap[fromLang] ?? "auto"
        let target = langMap[toLang] ?? "en"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlString = "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=\(source)|\(target)"
        guard let url = URL(string: urlString) else {
            outputText = L.t("翻译失败", lang)
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["responseData"] as? [String: Any],
                  let translated = responseData["translatedText"] as? String else {
                outputText = L.t("翻译失败", lang)
                return
            }
            outputText = translated
        } catch {
            outputText = L.t("翻译失败", lang) + "：\(error.localizedDescription)"
        }
    }
}
