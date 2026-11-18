import Foundation
import UIKit
import CoreML
import StableDiffusion

struct GenerationRequest {
    var prompt: String
    var negativePrompt: String
    var steps: Int
    var guidance: Float
    var seed: UInt32?
    var scheduler: StableDiffusionScheduler
    var startingImage: CGImage?
    var strength: Float
}

struct GenerationResult {
    let image: UIImage
    let seed: UInt32
    let seconds: Double
}

private final class CancelFlag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
}

/// Holds the loaded Core ML pipeline. Only used on the generator's serial queue.
private final class Engine: @unchecked Sendable {
    private var current: StableDiffusionPipeline?
    private var loadedModelID: String?

    func pipeline(for model: InstalledModel) throws -> StableDiffusionPipeline {
        if let current, loadedModelID == model.id { return current }
        unload()

        let mlConfig = MLModelConfiguration()
        // split_einsum models are built for the Apple Neural Engine.
        mlConfig.computeUnits = .cpuAndNeuralEngine

        let new = try StableDiffusionPipeline(
            resourcesAt: model.resourceURL,
            controlNet: [],
            configuration: mlConfig,
            disableSafety: true,
            reduceMemory: true
        )
        // First load compiles the model for the Neural Engine; this can take a couple of minutes once.
        try new.loadResources()
        current = new
        loadedModelID = model.id
        return new
    }

    func unload() {
        current?.unloadResources()
        current = nil
        loadedModelID = nil
    }
}

/// Runs Stable Diffusion entirely on-device (Neural Engine + CPU). No network use.
@MainActor
final class Generator: ObservableObject {
    enum Status: Equatable {
        case idle
        case loading
        case generating(step: Int, total: Int)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastResult: UIImage?

    var isBusy: Bool {
        switch status {
        case .loading, .generating: return true
        default: return false
        }
    }

    private let engine = Engine()
    private let queue = DispatchQueue(label: "pocketstudio.generator", qos: .userInitiated)
    private let cancelFlag = CancelFlag()

    func cancel() { cancelFlag.set(true) }

    func generate(_ request: GenerationRequest, model: InstalledModel,
                  completion: @escaping @MainActor (GenerationResult) -> Void) {
        guard !isBusy else { return }
        cancelFlag.set(false)
        status = .loading
        UIApplication.shared.isIdleTimerDisabled = true

        let engine = self.engine
        let cancelFlag = self.cancelFlag

        queue.async { [weak self] in
            do {
                let pipeline = try engine.pipeline(for: model)
                let seed = request.seed ?? UInt32.random(in: 0...UInt32.max)

                var config = StableDiffusionPipeline.Configuration(prompt: request.prompt)
                config.negativePrompt = request.negativePrompt
                config.stepCount = request.steps
                config.guidanceScale = request.guidance
                config.seed = seed
                config.imageCount = 1
                config.disableSafety = true
                config.schedulerType = request.scheduler
                if let start = request.startingImage, model.supportsImageToImage {
                    config.startingImage = start
                    config.strength = request.strength
                }

                Task { @MainActor in self?.status = .generating(step: 0, total: request.steps) }
                let started = Date()
                let images = try pipeline.generateImages(configuration: config) { progress in
                    let step = progress.step + 1, total = progress.stepCount
                    Task { @MainActor in
                        if self?.isBusy == true { self?.status = .generating(step: step, total: total) }
                    }
                    return !cancelFlag.isSet
                }
                let elapsed = Date().timeIntervalSince(started)
                let cgImage: CGImage? = images.first ?? nil
                let wasCancelled = cancelFlag.isSet

                Task { @MainActor in
                    guard let self else { return }
                    UIApplication.shared.isIdleTimerDisabled = false
                    if let cgImage {
                        let image = UIImage(cgImage: cgImage)
                        self.lastResult = image
                        self.status = .idle
                        completion(GenerationResult(image: image, seed: seed, seconds: elapsed))
                    } else {
                        self.status = wasCancelled ? .idle : .failed("No image was produced.")
                    }
                }
            } catch {
                // Drop the pipeline so the next attempt reloads cleanly.
                engine.unload()
                let message = error.localizedDescription
                Task { @MainActor in
                    UIApplication.shared.isIdleTimerDisabled = false
                    self?.status = .failed(message)
                }
            }
        }
    }

    /// Frees model memory (e.g. when a model is deleted).
    func unload() {
        let engine = self.engine
        queue.async { engine.unload() }
    }
}

extension UIImage {
    /// Center-crops and resizes to a square CGImage (Stable Diffusion 1.5 expects 512×512).
    func squareCGImage(side: CGFloat = 512) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let scale = max(side / size.width, side / size.height)
        let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        let rendered = renderer.image { _ in
            self.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return rendered.cgImage
    }
}
