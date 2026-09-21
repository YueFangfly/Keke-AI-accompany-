import Foundation
import UIKit

struct StickerItem: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var fileName: String
}

@MainActor
final class StickerStore: ObservableObject {
    @Published var stickers: [StickerItem] = []
    private let personaId: String

    private var stickerDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Stickers/\(personaId)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(personaId)_stickers.json")
    }

    init(personaId: String = "keke") {
        self.personaId = personaId
        loadIndex()
    }

    @discardableResult
    func addSticker(image: UIImage) -> StickerItem? {
        let size: CGFloat = 300
        let resized = resize(image, to: CGSize(width: size, height: size))
        guard let data = resized.pngData() else { return nil }
        let fileName = "\(UUID().uuidString).png"
        let url = stickerDir.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
        } catch {
            return nil
        }
        let item = StickerItem(fileName: fileName)
        stickers.append(item)
        saveIndex()
        return item
    }

    func deleteSticker(_ sticker: StickerItem) {
        stickers.removeAll { $0.id == sticker.id }
        let url = stickerDir.appendingPathComponent(sticker.fileName)
        try? FileManager.default.removeItem(at: url)
        saveIndex()
    }

    func loadImage(for sticker: StickerItem) -> UIImage? {
        let url = stickerDir.appendingPathComponent(sticker.fileName)
        return UIImage(contentsOfFile: url.path)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let items = try? JSONDecoder().decode([StickerItem].self, from: data) else { return }
        stickers = items.filter { FileManager.default.fileExists(atPath: stickerDir.appendingPathComponent($0.fileName).path) }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(stickers) else { return }
        try? data.write(to: indexURL)
    }

    private func resize(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let widthRatio = targetSize.width / image.size.width
        let heightRatio = targetSize.height / image.size.height
        let ratio = min(widthRatio, heightRatio, 1.0)
        let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
