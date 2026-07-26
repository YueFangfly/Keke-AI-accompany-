import SwiftUI
import UniformTypeIdentifiers

/// 探索 → 阅读：书架 + 阅读器。克克会自己往下读、留批注，也会回我留的批注，
/// 深夜还在看书可能被她抓个现行催睡觉
struct BookListView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var books: BookService
    @State private var showImporter = false
    @State private var importError: String?
    @State private var activeBook: Book?

    private var lang: AppLanguage { store.appLanguage }

    var body: some View {
        VStack(spacing: 0) {
            importButton
            if let importError {
                Text(importError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.top, 6)
            }
            if books.books.isEmpty {
                emptyState
            } else {
                bookList
            }
        }
        .background(Theme.background)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.pdf, .plainText, .html, .text]) { result in
            guard case .success(let url) = result else { return }
            if books.importBook(from: url) == nil {
                importError = L.t("这本书读不出来", lang)
            } else {
                importError = nil
            }
        }
        .slideOverCover(item: $activeBook) { book in
            ReaderView(book: book, onBack: { activeBook = nil })
                .environmentObject(store)
                .environmentObject(books)
        }
    }

    private var importButton: some View {
        Button {
            showImporter = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text(L.t("导入一本书", lang))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 13).fill(Theme.accent))
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("📖")
                .font(.system(size: 44))
            Text(L.t("还没有书\n导入 pdf / txt / html / md，克克会陪你一起看", lang))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bookList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(books.books) { book in
                    Button {
                        activeBook = book
                    } label: {
                        bookRow(book)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            books.delete(book)
                        } label: {
                            Label(L.t("删除", lang), systemImage: "trash")
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func bookRow(_ book: Book) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(Int(book.progressPercent * 100))%")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }
}

/// 阅读器：正文按段落显示，长按一段可以留批注；克克的批注混在段落下面一起显示
struct ReaderView: View {
    @EnvironmentObject var store: ChatStore
    @EnvironmentObject var books: BookService
    let book: Book
    let onBack: () -> Void

    @State private var paragraphs: [String] = []
    @State private var nightNagText: String?
    @State private var replyTarget: BookNote?
    @State private var noteText = ""
    @State private var showNoteInput = false
    @State private var noteAnchorIndex: Int?
    @State private var didScrollToStart = false
    @State private var currentParagraph = 0
    @State private var showBookmarks = false

    private var lang: AppLanguage { store.appLanguage }
    private var currentBook: Book { books.books.first(where: { $0.id == book.id }) ?? book }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        paragraphRow(index: index, text: paragraph)
                            .id(index)
                            .onAppear {
                                currentParagraph = index
                                books.updateMyProgress(book, paragraphIndex: index)
                            }
                    }
                }
                .padding(16)
            }
            .onAppear {
                paragraphs = books.paragraphs(for: book)
                guard !didScrollToStart, book.myProgress > 0 else { return }
                didScrollToStart = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    proxy.scrollTo(book.myProgress, anchor: .top)
                }
            }
            .safeAreaInset(edge: .top) { topBar }
            .sheet(isPresented: $showBookmarks) {
                bookmarksList(proxy: proxy)
            }
        }
        .background(Theme.background)
        .overlay(alignment: .top) {
            if let nightNagText {
                Text(nightNagText)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassCard(cornerRadius: 14)
                    .padding(.horizontal, 30)
                    .padding(.top, 54)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showNoteInput {
                noteInputBar
            }
        }
        .task {
            guard let nag = await books.maybeNightNag(book: book, store: store) else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { nightNagText = nag }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation { nightNagText = nil }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(book.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                let preview = currentParagraph < paragraphs.count ? paragraphs[currentParagraph] : ""
                books.addBookmark(bookID: book.id, paragraphIndex: currentParagraph, preview: preview)
            } label: {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
            }
            Button {
                showBookmarks = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(Theme.background)
    }

    private func bookmarksList(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            Text(L.t("书签", lang))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)
                .padding(.bottom, 10)
            if currentBook.bookmarks.isEmpty {
                Text(L.t("还没有书签，读到喜欢的地方点右上角的书签图标存一个", lang))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 30)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(currentBook.bookmarks) { mark in
                            Button {
                                showBookmarks = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    proxy.scrollTo(mark.paragraphIndex, anchor: .top)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mark.preview)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(mark.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .glassCard(cornerRadius: 10)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    books.removeBookmark(mark, from: book.id)
                                } label: {
                                    Label(L.t("删除", lang), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(Theme.background)
    }

    private func paragraphRow(index: Int, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .onLongPressGesture {
                    noteAnchorIndex = index
                    replyTarget = nil
                    withAnimation { showNoteInput = true }
                }
            ForEach(books.notes(for: book).filter { $0.paragraphIndex == index }) { note in
                noteRow(note)
            }
        }
    }

    private func noteRow(_ note: BookNote) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(note.author == .keke ? "🐱" : "🌙")
                .font(.caption)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    replyTarget = note
                    noteAnchorIndex = note.paragraphIndex
                    withAnimation { showNoteInput = true }
                } label: {
                    Text(L.t("回复", lang))
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.backgroundDeep.opacity(0.4)))
    }

    private var noteInputBar: some View {
        VStack(spacing: 6) {
            if let replyTarget {
                HStack(spacing: 6) {
                    Text(L.t("回复", lang) + " " + String(replyTarget.text.prefix(20)))
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button {
                        self.replyTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(L.t("留一句批注…", lang), text: $noteText)
                    .font(.caption)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.backgroundDeep.opacity(0.6)))
                Button {
                    guard let anchor = noteAnchorIndex else { return }
                    books.addNote(bookID: book.id, paragraphIndex: anchor, text: noteText, replyTo: replyTarget)
                    noteText = ""
                    replyTarget = nil
                    showNoteInput = false
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.accent))
                }
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    showNoteInput = false
                    noteText = ""
                    replyTarget = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(12)
        .background(Theme.backgroundDeep)
    }
}
