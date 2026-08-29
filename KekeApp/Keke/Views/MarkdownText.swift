import SwiftUI
import UIKit

// 聊天气泡里的 Markdown 渲染。
//
// 在这之前正文是裸的 Text，模型回的列表、加粗、代码块全是原始符号。
//
// 分两层：MarkdownParser 把文本拆成块（纯逻辑，不碰 SwiftUI，能单独验证），
// MarkdownText 负责画。行内的加粗/斜体/行内代码/链接交给系统的
// AttributedString(markdown:) 解析，块级的标题、列表、引用、代码块自己排。
//
// 只做聊天里真正会遇到的那些。表格和公式没做——它们要的排版复杂得多，
// 现在硬凑不如原样显示。

// MARK: - 块

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(text: String, depth: Int)
    case numbered(marker: String, text: String, depth: Int)
    case quote(String)
    case code(language: String?, code: String)
    /// 分割线
    case rule
}

// MARK: - 解析

enum MarkdownParser {

    /// 缩进多少个空格算一层。Tab 按 4 个空格算
    private static let spacesPerDepth = 2
    /// 列表最多认这么多层，再深了视觉上也分不出来
    private static let maxDepth = 3

    static func blocks(from raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []

        // 代码块状态。fence 记住是 ``` 还是 ~~~，得用同样的符号才算闭合
        var fence: String?
        var codeLanguage: String?
        var code: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(quote.joined(separator: "\n")))
            quote.removeAll()
        }
        func flushAll() {
            flushParagraph()
            flushQuote()
        }

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // ── 代码块里：除了闭合符，什么都原样收下
            if let current = fence {
                if trimmed.hasPrefix(current) {
                    blocks.append(.code(language: codeLanguage, code: code.joined(separator: "\n")))
                    code.removeAll()
                    codeLanguage = nil
                    fence = nil
                } else {
                    code.append(line)
                }
                continue
            }

            // ── 代码块开头
            if let marker = openingFence(trimmed) {
                flushAll()
                fence = marker.fence
                codeLanguage = marker.language
                continue
            }

            // ── 空行：段落和引用到此为止
            if trimmed.isEmpty {
                flushAll()
                continue
            }

            // ── 分割线
            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                continue
            }

            // ── 标题
            if let heading = parseHeading(trimmed) {
                flushAll()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            // ── 引用：连着的几行合成一段
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var content = String(trimmed.dropFirst())
                if content.hasPrefix(" ") { content.removeFirst() }
                quote.append(content)
                continue
            }
            flushQuote()

            // ── 列表
            if let item = parseListItem(line) {
                flushParagraph()
                switch item.marker {
                case .bullet:
                    blocks.append(.bullet(text: item.text, depth: item.depth))
                case .numbered(let label):
                    blocks.append(.numbered(marker: label, text: item.text, depth: item.depth))
                }
                continue
            }

            // ── 普通正文
            paragraph.append(line)
        }

        // 收尾。代码块没闭合也要交出去——流式的时候正文是一个字一个字来的，
        // 收到一半必然是"开了还没关"的状态，这时候不显示就等于闪一下
        if fence != nil {
            blocks.append(.code(language: codeLanguage, code: code.joined(separator: "\n")))
        }
        flushAll()
        return blocks
    }

    /// ``` 或 ~~~ 开头？顺便把语言名取出来
    private static func openingFence(_ trimmed: String) -> (fence: String, language: String?)? {
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            let rest = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return (marker, rest.isEmpty ? nil : rest)
        }
        return nil
    }

    /// 三个以上的 - * _ 单独成行就是分割线
    private static func isRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        for ch in ["-", "*", "_"] where trimmed.allSatisfy({ String($0) == ch }) {
            return true
        }
        return false
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        var level = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index] == "#", level < 6 {
            level += 1
            index = trimmed.index(after: index)
        }
        guard level > 0, index < trimmed.endIndex, trimmed[index] == " " else { return nil }
        let text = String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private enum ListMarker {
        case bullet
        case numbered(String)
    }

    private static func parseListItem(_ line: String) -> (marker: ListMarker, text: String, depth: Int)? {
        // 前导空白算缩进层级，Tab 当 4 个空格
        var spaces = 0
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == " " { spaces += 1 }
            else if line[index] == "\t" { spaces += 4 }
            else { break }
            index = line.index(after: index)
        }
        let depth = min(spaces / spacesPerDepth, maxDepth)
        let rest = String(line[index...])

        // 无序：- * + 后面跟一个空格
        for bullet in ["- ", "* ", "+ "] where rest.hasPrefix(bullet) {
            let text = String(rest.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (.bullet, text, depth)
        }

        // 有序：数字后跟 . 或 )
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let afterDigits = rest.dropFirst(digits.count)
        guard let separator = afterDigits.first, separator == "." || separator == ")",
              afterDigits.dropFirst().hasPrefix(" ") else { return nil }
        let text = String(afterDigits.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (.numbered("\(digits)\(separator)"), text, depth)
    }

    // MARK: - 行内

    /// 行内的加粗、斜体、行内代码、链接交给系统解析。
    /// 解析不了就原样返回——流式下经常收到 `**还没写完` 这种半截语法，不能崩也不能空
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard var attributed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        // 行内代码换成等宽。先把范围收集起来再改，
        // 边遍历 runs 边改属性会让遍历本身失效
        let codeRanges = attributed.runs.compactMap { run -> Range<AttributedString.Index>? in
            run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
        }
        for range in codeRanges {
            attributed[range].font = .system(.footnote, design: .monospaced)
        }
        return attributed
    }
}

// MARK: - 渲染

struct MarkdownText: View {
    let text: String
    var textColor: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownParser.blocks(from: text).enumerated()), id: \.offset) { item in
                view(for: item.element)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownParser.inline(text))
                .font(headingFont(level))
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Text(MarkdownParser.inline(text))
                .font(.subheadline)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text, let depth):
            listRow(marker: "•", text: text, depth: depth)

        case .numbered(let marker, let text, let depth):
            listRow(marker: marker, text: text, depth: depth)

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: 3)
                Text(MarkdownParser.inline(text))
                    .font(.subheadline)
                    .foregroundStyle(textColor.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .rule:
            Rectangle()
                .fill(textColor.opacity(0.15))
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    private func listRow(marker: String, text: String, depth: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(marker)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(textColor.opacity(0.7))
            Text(MarkdownParser.inline(text))
                .font(.subheadline)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(depth) * 14)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3.weight(.semibold)
        case 2: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }
}

// MARK: - 代码块

/// 代码块：等宽、可横向滚动、右上角能一键复制。
/// 横向滚动是必须的——长行如果自动折行，缩进就全乱了，代码会变得没法读
private struct CodeBlockView: View {
    @EnvironmentObject private var store: ChatStore
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(L.t(copied ? "已复制" : "复制", store.appLanguage))
                            .font(.caption2)
                    }
                    .foregroundStyle(copied ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.textSecondary.opacity(0.12), lineWidth: 1)
        )
    }
}
