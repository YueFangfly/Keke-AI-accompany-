import Foundation

/// 阅读：导入书（pdf/txt/html/md），我和克克各自有阅读进度，
/// 克克会自己往下读、留批注，也会回我留的批注——都不是秒回，是她"自己读到了才回"
@MainActor
final class BookService: ObservableObject {
    let personaId: String
    @Published var books: [Book] = []
    @Published var notes: [BookNote] = []

    private var booksDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_books", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private var catalogURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_books.json")
    }
    private var notesURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_book_notes.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        load()
    }

    // MARK: - 导入 / 正文

    @discardableResult
    func importBook(from url: URL) -> Book? {
        guard let text = Attachments.extractBookText(from: url) else { return nil }
        let paragraphs = Self.paragraphs(from: text)
        guard !paragraphs.isEmpty else { return nil }
        let fileName = "book_\(UUID().uuidString).txt"
        guard (try? text.write(to: booksDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)) != nil else {
            return nil
        }
        let title = url.deletingPathExtension().lastPathComponent
        let book = Book(title: title, fileName: fileName, totalParagraphs: paragraphs.count)
        books.insert(book, at: 0)
        save()
        return book
    }

    func paragraphs(for book: Book) -> [String] {
        guard let text = try? String(contentsOf: booksDir.appendingPathComponent(book.fileName), encoding: .utf8) else {
            return []
        }
        return Self.paragraphs(from: text)
    }

    static func paragraphs(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func delete(_ book: Book) {
        try? FileManager.default.removeItem(at: booksDir.appendingPathComponent(book.fileName))
        books.removeAll { $0.id == book.id }
        notes.removeAll { $0.bookID == book.id }
        save()
    }

    // MARK: - 进度 / 批注

    func updateMyProgress(_ book: Book, paragraphIndex: Int) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].myProgress = max(books[index].myProgress, paragraphIndex)
        books[index].lastOpenedAt = Date()
        save()
    }

    // MARK: - 书签

    func addBookmark(bookID: UUID, paragraphIndex: Int, preview: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let mark = Bookmark(paragraphIndex: paragraphIndex, preview: String(preview.prefix(40)))
        books[index].bookmarks.append(mark)
        save()
    }

    func removeBookmark(_ bookmark: Bookmark, from bookID: UUID) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    func notes(for book: Book) -> [BookNote] {
        notes.filter { $0.bookID == book.id }.sorted { $0.paragraphIndex < $1.paragraphIndex }
    }

    func addNote(bookID: UUID, paragraphIndex: Int, text: String, replyTo: BookNote? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = BookNote(bookID: bookID, author: .me, paragraphIndex: paragraphIndex,
                            text: trimmed, replyToID: replyTo?.id)
        notes.append(note)
        save()
    }

    // MARK: - 克克自己读书

    /// App 回到前台时调用：每本书都有小概率让她"自己往下读一段"，
    /// 有未回的批注时优先回批注，不然就自己往下翻
    func maybeReadAlong(store: ChatStore) async {
        guard !store.apiKey.isEmpty else { return }
        for book in books {
            guard Double.random(in: 0..<1) < 0.3, canReactAgain(bookID: book.id) else { continue }
            await readAlong(book: book, store: store)
        }
    }

    private func readAlong(book: Book, store: ChatStore) async {
        let allParagraphs = paragraphs(for: book)
        guard !allParagraphs.isEmpty else { return }

        let myUnanswered = notes(for: book).filter { note in
            note.author == .me && !notes.contains { $0.replyToID == note.id }
        }

        if let target = myUnanswered.randomElement() {
            let excerpt = excerptAround(target.paragraphIndex, in: allParagraphs)
            guard let reply = try? await ClaudeService.generateBookNote(
                bookTitle: book.title, excerpt: excerpt, replyTo: target.text,
                userName: store.myName,
                provider: store.provider, apiKey: store.apiKey, model: store.model,
                systemPrompt: store.effectiveSystemPrompt
            ) else { return }
            notes.append(BookNote(bookID: book.id, author: .keke, paragraphIndex: target.paragraphIndex,
                                  text: reply, replyToID: target.id))
            markReacted(bookID: book.id)
            save()
            return
        }

        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        let start = books[index].kekeProgress
        guard start < allParagraphs.count - 1 else { return }
        let step = Int.random(in: 8...40)
        let newIndex = min(start + step, allParagraphs.count - 1)
        let excerpt = excerptAround(newIndex, in: allParagraphs)

        guard let note = try? await ClaudeService.generateBookNote(
            bookTitle: book.title, excerpt: excerpt, replyTo: nil,
            userName: store.myName,
            provider: store.provider, apiKey: store.apiKey, model: store.model,
            systemPrompt: store.effectiveSystemPrompt
        ) else {
            books[index].kekeProgress = newIndex
            save()
            return
        }
        books[index].kekeProgress = newIndex
        notes.append(BookNote(bookID: book.id, author: .keke, paragraphIndex: newIndex, text: note))
        markReacted(bookID: book.id)
        save()
    }

    private func excerptAround(_ paragraphIndex: Int, in paragraphs: [String]) -> String {
        let start = max(0, paragraphIndex - 2)
        let end = min(paragraphs.count, paragraphIndex + 1)
        return paragraphs[start..<end].joined(separator: "\n")
    }

    /// 每本书跟她互动的冷却，至少隔 3 小时，避免一次刷一堆批注
    private func canReactAgain(bookID: UUID) -> Bool {
        let key = "\(personaId)_book_react_\(bookID.uuidString)"
        let last = UserDefaults.standard.double(forKey: key)
        return Date().timeIntervalSince1970 - last > 3 * 3600
    }

    private func markReacted(bookID: UUID) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "\(personaId)_book_react_\(bookID.uuidString)")
    }

    // MARK: - 深夜偷偷看书

    /// 打开阅读器时调用：深夜还在看书，克克可能抓个现行催睡觉，一天只抓一次
    func maybeNightNag(book: Book, store: ChatStore) async -> String? {
        guard !store.apiKey.isEmpty else { return nil }
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 23 || hour < 5 else { return nil }
        let dayKey = "\(personaId)_book_nightnag_\(Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970))"
        guard !UserDefaults.standard.bool(forKey: dayKey) else { return nil }
        UserDefaults.standard.set(true, forKey: dayKey)
        return try? await ClaudeService.generateNightReadingNag(
            bookTitle: book.title, userName: store.myName, provider: store.provider, apiKey: store.apiKey,
            model: store.model, systemPrompt: store.effectiveSystemPrompt
        )
    }

    // MARK: - 持久化

    private func save() {
        if let data = try? JSONEncoder().encode(books) {
            try? data.write(to: catalogURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: notesURL, options: .atomic)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: catalogURL),
           let saved = try? JSONDecoder().decode([Book].self, from: data) {
            books = saved
        }
        if let data = try? Data(contentsOf: notesURL),
           let saved = try? JSONDecoder().decode([BookNote].self, from: data) {
            notes = saved
        }
    }
}
