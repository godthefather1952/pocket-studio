import Foundation
import UIKit

struct GalleryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let prompt: String
    let negativePrompt: String
    let seed: UInt32
    let steps: Int
    let guidance: Float
    let modelName: String
    let seconds: Double
    let imageToImage: Bool

    var fileName: String { "\(id.uuidString).png" }
}

/// Saves generated images as PNGs in Documents/Gallery (also visible in the Files app).
@MainActor
final class Gallery: ObservableObject {
    @Published private(set) var items: [GalleryItem] = []

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Gallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexURL: URL { Self.directory.appendingPathComponent("index.json") }

    init() { load() }

    func url(for item: GalleryItem) -> URL { Self.directory.appendingPathComponent(item.fileName) }

    func image(for item: GalleryItem) -> UIImage? { UIImage(contentsOfFile: url(for: item).path) }

    @discardableResult
    func add(_ image: UIImage, item: GalleryItem) -> GalleryItem {
        if let data = image.pngData() {
            try? data.write(to: url(for: item))
        }
        items.insert(item, at: 0)
        save()
        return item
    }

    func delete(_ item: GalleryItem) {
        try? FileManager.default.removeItem(at: url(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([GalleryItem].self, from: data) else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
