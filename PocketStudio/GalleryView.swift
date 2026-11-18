import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var gallery: Gallery
    @State private var selected: GalleryItem?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    var body: some View {
        NavigationStack {
            Group {
                if gallery.items.isEmpty {
                    ContentUnavailableView("No images yet",
                                           systemImage: "photo.on.rectangle.angled",
                                           description: Text("Images you generate are saved here and in the Files app under Pocket Studio › Gallery."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(gallery.items) { item in
                                Thumbnail(url: gallery.url(for: item))
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()
                                    .onTapGesture { selected = item }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle("Gallery")
            .sheet(item: $selected) { item in
                GalleryDetail(item: item) { selected = nil }
            }
        }
    }
}

private struct Thumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Color.white.opacity(0.06)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .task(id: url) {
                image = await Task.detached(priority: .utility) {
                    UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 300, height: 300))
                }.value
            }
    }
}

private struct GalleryDetail: View {
    @EnvironmentObject var gallery: Gallery
    let item: GalleryItem
    let dismiss: () -> Void
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let image = gallery.image(for: item) {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        HStack {
                            Button {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                                saved = true
                            } label: {
                                Label(saved ? "Saved" : "Save to Photos",
                                      systemImage: saved ? "checkmark" : "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            ShareLink(item: gallery.url(for: item)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text(item.prompt).font(.body)
                    if !item.negativePrompt.isEmpty {
                        Text("Avoid: \(item.negativePrompt)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(item.modelName) · \(item.steps) steps · seed \(String(item.seed)) · \(String(format: "%.1fs", item.seconds))\(item.imageToImage ? " · from photo" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Copy prompt") { UIPasteboard.general.string = item.prompt }
                        .font(.footnote)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        gallery.delete(item)
                        dismiss()
                    } label: { Image(systemName: "trash") }
                }
            }
        }
    }
}
