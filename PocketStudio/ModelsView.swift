import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var generator: Generator
    @State private var showImporter = false
    @State private var pendingDelete: InstalledModel?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ModelCatalog.models) { model in
                        CatalogRow(model: model)
                    }
                } header: {
                    Text("Download (one time)")
                } footer: {
                    Text("Use Wi-Fi and keep the app open until it finishes. After that, generation is 100% on-device with no internet needed.")
                }

                if !models.installed.isEmpty {
                    Section("Installed on this iPhone") {
                        ForEach(models.installed) { model in
                            HStack {
                                Image(systemName: models.selected?.id == model.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading) {
                                    Text(model.name)
                                    Text(model.supportsImageToImage ? "Text-to-image + photo-to-image" : "Text-to-image")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { models.selectedID = model.id }
                            .swipeActions {
                                Button("Delete", role: .destructive) { pendingDelete = model }
                            }
                        }
                    }
                }

                let imports = models.phases.filter { $0.key.hasPrefix("imported-") }
                if !imports.isEmpty {
                    Section("Importing") {
                        ForEach(imports.keys.sorted(), id: \.self) { id in
                            PhaseView(phase: imports[id]!, onCancel: nil, onDismiss: { models.clearFailure(id) })
                        }
                    }
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import model from Files…", systemImage: "folder.badge.plus")
                    }
                } footer: {
                    Text("Advanced: import any compiled Core ML Stable Diffusion 1.x/2.x model (a .zip or folder containing TextEncoder.mlmodelc, Unet.mlmodelc, VAEDecoder.mlmodelc, vocab.json and merges.txt). SDXL and video models aren't supported.")
                }
            }
            .navigationTitle("Models")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip, .folder]) { result in
                if case .success(let url) = result {
                    Task { await models.importFromFiles(url) }
                }
            }
            .confirmationDialog("Delete \(pendingDelete?.name ?? "model")?",
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let model = pendingDelete {
                        generator.unload()
                        models.delete(model)
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("You'd need to download it again to use it.")
            }
        }
    }
}

private struct CatalogRow: View {
    @EnvironmentObject var models: ModelManager
    let model: CatalogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.headline)
                    Text(model.sizeLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if models.isInstalled(model.id) {
                    Label("Installed", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                } else if models.phases[model.id] == nil {
                    Button("Download") { models.download(model) }
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(model.detail).font(.caption).foregroundStyle(.secondary)
            if let phase = models.phases[model.id] {
                PhaseView(phase: phase,
                          onCancel: { models.cancelDownload(model.id) },
                          onDismiss: { models.clearFailure(model.id) })
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PhaseView: View {
    let phase: ModelPhase
    let onCancel: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        switch phase {
        case .downloading(let f):
            HStack {
                ProgressView(value: f)
                Text("\(Int(f * 100))%").font(.caption.monospacedDigit())
                if let onCancel {
                    Button(action: onCancel) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
        case .unpacking(let f):
            VStack(alignment: .leading) {
                ProgressView(value: f)
                Text("Unpacking… \(Int(f * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption)
                Spacer()
                Button("OK", action: onDismiss).font(.caption).buttonStyle(.borderless)
            }
        }
    }
}
