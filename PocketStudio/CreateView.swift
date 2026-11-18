import SwiftUI
import PhotosUI
import StableDiffusion

struct CreateView: View {
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var gallery: Gallery
    @EnvironmentObject var generator: Generator

    let goToModels: () -> Void

    @AppStorage("prompt") private var prompt = "a cozy cabin in a snowy forest at dusk, warm window light, highly detailed, cinematic"
    @AppStorage("negativePrompt") private var negativePrompt = "blurry, low quality, deformed, watermark, text"
    @AppStorage("steps") private var steps = 25.0
    @AppStorage("guidance") private var guidance = 7.5
    @AppStorage("useDPM") private var useDPM = true
    @State private var seedText = ""
    @State private var lastSeed: UInt32?
    @State private var lastSeconds: Double?

    @State private var pickerItem: PhotosPickerItem?
    @State private var startImage: UIImage?
    @State private var strength = 0.6
    @State private var savedToPhotos = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if models.installed.isEmpty {
                        noModelCard
                    } else {
                        modelPicker
                        resultArea
                        promptSection
                        imageToImageSection
                        settingsSection
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Pocket Studio")
            .safeAreaInset(edge: .bottom) {
                if !models.installed.isEmpty { generateBar }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { promptFocused = false }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    startImage = image
                }
            }
        }
    }

    // MARK: Sections

    private var noModelCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "cpu").font(.system(size: 44)).foregroundStyle(.purple)
            Text("No model installed yet").font(.title3.bold())
            Text("Download a model once (about 1.6 GB on Wi-Fi). After that, every image is generated on this iPhone with no internet.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Go to Models", action: goToModels)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var modelPicker: some View {
        if models.installed.count > 1 {
            Picker("Model", selection: Binding(
                get: { models.selected?.id ?? "" },
                set: { models.selectedID = $0 })) {
                ForEach(models.installed) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
        } else if let model = models.selected {
            Label(model.name, systemImage: "cpu")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var resultArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06))
            if let image = generator.lastResult {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .opacity(generator.isBusy ? 0.35 : 1)
            } else if !generator.isBusy {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.largeTitle)
                    Text("Your image will appear here").font(.footnote)
                }
                .foregroundStyle(.secondary)
            }
            statusOverlay
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottom) {
            if let image = generator.lastResult, !generator.isBusy {
                HStack {
                    if let lastSeed {
                        Button {
                            seedText = String(lastSeed)
                        } label: {
                            Label("Seed \(lastSeed)", systemImage: "pin")
                        }
                        .font(.caption)
                    }
                    if let lastSeconds {
                        Text(String(format: "%.1fs", lastSeconds)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        savedToPhotos = true
                    } label: {
                        Image(systemName: savedToPhotos ? "checkmark" : "square.and.arrow.down")
                    }
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Pocket Studio image", image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch generator.status {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading model…").font(.subheadline.bold())
                Text("The very first load prepares the model for the Neural Engine and can take 1–3 minutes. Later loads are quick.")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .padding()
        case .generating(let step, let total):
            VStack(spacing: 10) {
                ProgressView(value: Double(step), total: Double(max(total, 1)))
                    .frame(width: 200)
                Text("Step \(step) of \(total)").font(.subheadline.monospacedDigit())
                Button("Cancel", role: .cancel) { generator.cancel() }
                    .buttonStyle(.bordered)
            }
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.title)
                Text(message).font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.orange)
            .padding()
        case .idle:
            EmptyView()
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt").font(.headline)
            TextField("Describe the image…", text: $prompt, axis: .vertical)
                .lineLimit(3...6)
                .focused($promptFocused)
                .padding(12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            Text("Avoid").font(.subheadline).foregroundStyle(.secondary)
            TextField("Things to leave out…", text: $negativePrompt, axis: .vertical)
                .lineLimit(1...3)
                .focused($promptFocused)
                .padding(12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var imageToImageSection: some View {
        if let model = models.selected, model.supportsImageToImage {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Start from a photo").font(.headline)
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(startImage == nil ? "Choose" : "Change", systemImage: "photo")
                    }
                }
                if let startImage {
                    HStack(alignment: .top, spacing: 12) {
                        Image(uiImage: startImage)
                            .resizable().scaledToFill()
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading) {
                            Text("Change amount: \(Int(strength * 100))%").font(.subheadline)
                            Slider(value: $strength, in: 0.1...0.95)
                            Button("Remove photo", role: .destructive) {
                                self.startImage = nil
                                pickerItem = nil
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    Text("Optional: restyle one of your photos instead of starting from scratch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var settingsSection: some View {
        DisclosureGroup("Settings") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading) {
                    Text("Steps: \(Int(steps))").font(.subheadline)
                    Slider(value: $steps, in: 8...50, step: 1)
                    Text("More steps = more detail, slower. 20–30 is a good range.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(String(format: "Prompt strength: %.1f", guidance)).font(.subheadline)
                    Slider(value: $guidance, in: 1...15, step: 0.5)
                }
                HStack {
                    Text("Seed").font(.subheadline)
                    TextField("Random", text: $seedText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($promptFocused)
                    if !seedText.isEmpty {
                        Button { seedText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Fast sampler (DPM++)", isOn: $useDPM)
                    .font(.subheadline)
            }
            .padding(.top, 8)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var generateBar: some View {
        Button {
            promptFocused = false
            startGeneration()
        } label: {
            Label(generator.isBusy ? "Generating…" : "Generate", systemImage: "wand.and.stars")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(generator.isBusy || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: Actions

    private func startGeneration() {
        guard let model = models.selected else { return }
        savedToPhotos = false
        let useStart = model.supportsImageToImage ? startImage?.squareCGImage() : nil
        let request = GenerationRequest(
            prompt: prompt,
            negativePrompt: negativePrompt,
            steps: Int(steps),
            guidance: Float(guidance),
            seed: UInt32(seedText),
            scheduler: useDPM ? .dpmSolverMultistepScheduler : .pndmScheduler,
            startingImage: useStart,
            strength: Float(strength)
        )
        let modelName = model.name
        let promptCopy = prompt, negCopy = negativePrompt, stepCount = Int(steps), g = Float(guidance)
        generator.generate(request, model: model) { result in
            lastSeed = result.seed
            lastSeconds = result.seconds
            gallery.add(result.image, item: GalleryItem(
                id: UUID(), date: Date(), prompt: promptCopy, negativePrompt: negCopy,
                seed: result.seed, steps: stepCount, guidance: g, modelName: modelName,
                seconds: result.seconds, imageToImage: useStart != nil))
        }
    }
}
