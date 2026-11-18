import Foundation
import UIKit
import ZIPFoundation

/// A model that can be downloaded from inside the app (one time, then it runs offline).
struct CatalogModel: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let sizeLabel: String
    let downloadURL: URL
}

enum ModelCatalog {
    static let models: [CatalogModel] = [
        CatalogModel(
            id: "sd15-palettized-ane",
            name: "Stable Diffusion 1.5",
            detail: "Apple's 6-bit Neural Engine build. 512×512 images, about 5–15 s each on an iPhone 16 Pro.",
            sizeLabel: "1.6 GB",
            downloadURL: URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized/resolve/main/coreml-stable-diffusion-v1-5-palettized_split_einsum_v2_compiled.zip")!
        )
    ]
}

/// A model that is installed on the phone and ready to run.
struct InstalledModel: Identifiable, Hashable {
    let id: String
    let name: String
    let resourceURL: URL

    var supportsImageToImage: Bool {
        FileManager.default.fileExists(atPath: resourceURL.appendingPathComponent("VAEEncoder.mlmodelc").path)
    }
}

enum ModelPhase: Equatable {
    case downloading(Double)
    case unpacking(Double)
    case failed(String)
}

enum ModelError: LocalizedError {
    case notAModel
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .notAModel:
            return "That doesn't look like a compiled Core ML Stable Diffusion model (no TextEncoder.mlmodelc / Unet.mlmodelc found)."
        case .badResponse(let code):
            return "Download failed (HTTP \(code))."
        }
    }
}

/// Thread-safe throttle so download progress doesn't flood the UI.
private final class ProgressThrottle: @unchecked Sendable {
    private var last: [String: Int] = [:]
    private let lock = NSLock()

    func shouldReport(_ id: String, _ fraction: Double) -> Bool {
        let bucket = Int(fraction * 200)
        lock.lock(); defer { lock.unlock() }
        if last[id] == bucket { return false }
        last[id] = bucket
        return true
    }
}

@MainActor
final class ModelManager: NSObject, ObservableObject {
    @Published private(set) var installed: [InstalledModel] = []
    @Published private(set) var phases: [String: ModelPhase] = [:]
    @Published var selectedID: String? {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedModelID") }
    }

    private var session: URLSession!
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private let throttle = ProgressThrottle()

    var selected: InstalledModel? {
        installed.first { $0.id == selectedID } ?? installed.first
    }

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 60 * 60 * 3
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        selectedID = UserDefaults.standard.string(forKey: "selectedModelID")
        refresh()
    }

    // MARK: - Installed models

    func refresh() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Self.modelsDirectory,
                                                includingPropertiesForKeys: [.isDirectoryKey],
                                                options: [.skipsHiddenFiles])) ?? []
        var found: [InstalledModel] = []
        for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let root = Self.findResourceRoot(in: dir) else { continue }
            let id = dir.lastPathComponent
            let name = (try? String(contentsOf: dir.appendingPathComponent("name.txt"), encoding: .utf8))
                ?? ModelCatalog.models.first(where: { $0.id == id })?.name
                ?? id
            found.append(InstalledModel(id: id, name: name, resourceURL: root))
        }
        installed = found
        if selectedID == nil || !found.contains(where: { $0.id == selectedID }) {
            selectedID = found.first?.id
        }
    }

    func isInstalled(_ id: String) -> Bool { installed.contains { $0.id == id } }

    func delete(_ model: InstalledModel) {
        try? FileManager.default.removeItem(at: Self.modelsDirectory.appendingPathComponent(model.id))
        refresh()
    }

    /// Finds the folder that holds TextEncoder.mlmodelc + Unet(.mlmodelc|Chunk1.mlmodelc) + vocab.json.
    nonisolated static func findResourceRoot(in dir: URL) -> URL? {
        let fm = FileManager.default
        func isRoot(_ url: URL) -> Bool {
            let has = { (name: String) in fm.fileExists(atPath: url.appendingPathComponent(name).path) }
            return has("TextEncoder.mlmodelc") && has("vocab.json") && has("merges.txt")
                && (has("Unet.mlmodelc") || has("UnetChunk1.mlmodelc"))
                && has("VAEDecoder.mlmodelc")
        }
        if isRoot(dir) { return dir }
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                    options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in e {
            if url.pathExtension == "mlmodelc" { e.skipDescendants(); continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir && isRoot(url) { return url }
        }
        return nil
    }

    // MARK: - Download

    func download(_ model: CatalogModel) {
        guard tasks[model.id] == nil else { return }
        phases[model.id] = .downloading(0)
        let task = session.downloadTask(with: model.downloadURL)
        task.taskDescription = model.id
        tasks[model.id] = task
        task.resume()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func cancelDownload(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        phases[id] = nil
        updateIdleTimer()
    }

    func clearFailure(_ id: String) {
        if case .failed = phases[id] { phases[id] = nil }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = !tasks.isEmpty
    }

    fileprivate func downloadFinished(id: String, zipURL: URL?, error: String?) {
        tasks[id] = nil
        updateIdleTimer()
        if let error {
            phases[id] = .failed(error)
            return
        }
        guard let zipURL else { return }
        let name = ModelCatalog.models.first(where: { $0.id == id })?.name ?? id
        Task { await installZip(zipURL, id: id, name: name, deleteZip: true) }
    }

    // MARK: - Install / import

    func installZip(_ zipURL: URL, id: String, name: String, deleteZip: Bool) async {
        phases[id] = .unpacking(0)
        UIApplication.shared.isIdleTimerDisabled = true
        let dest = Self.modelsDirectory.appendingPathComponent(id, isDirectory: true)
        let progress = Progress()
        let poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.phases[id] = .unpacking(progress.fractionCompleted)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        do {
            try await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                defer { if deleteZip { try? fm.removeItem(at: zipURL) } }
                try fm.unzipItem(at: zipURL, to: dest, progress: progress)
                guard ModelManager.findResourceRoot(in: dest) != nil else { throw ModelError.notAModel }
                try name.write(to: dest.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutableDest = dest
                try? mutableDest.setResourceValues(values)
            }.value
            poll.cancel()
            phases[id] = nil
            refresh()
            if selectedID == nil { selectedID = id }
        } catch {
            poll.cancel()
            try? FileManager.default.removeItem(at: dest)
            phases[id] = .failed(error.localizedDescription)
        }
        updateIdleTimer()
    }

    /// Import a model zip or an unzipped model folder picked from the Files app.
    func importFromFiles(_ url: URL) async {
        let isZip = url.pathExtension.lowercased() == "zip"
        let baseName = url.deletingPathExtension().lastPathComponent
        let id = "imported-" + baseName.replacingOccurrences(of: " ", with: "-")
        phases[id] = .unpacking(0)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            if isZip {
                // Copy out of the security-scoped location first.
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
                try await Task.detached { try FileManager.default.copyItem(at: url, to: tmp) }.value
                await installZip(tmp, id: id, name: baseName, deleteZip: true)
            } else {
                let dest = Self.modelsDirectory.appendingPathComponent(id, isDirectory: true)
                try await Task.detached {
                    let fm = FileManager.default
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.copyItem(at: url, to: dest)
                    guard ModelManager.findResourceRoot(in: dest) != nil else {
                        try? fm.removeItem(at: dest)
                        throw ModelError.notAModel
                    }
                    try baseName.write(to: dest.appendingPathComponent("name.txt"), atomically: true, encoding: .utf8)
                }.value
                phases[id] = nil
                refresh()
            }
        } catch {
            phases[id] = .failed(error.localizedDescription)
        }
    }
}

// MARK: - URLSession delegate

extension ModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        guard throttle.shouldReport(id, fraction) else { return }
        Task { @MainActor in
            if case .downloading = self.phases[id] { self.phases[id] = .downloading(fraction) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let code = http.statusCode
            Task { @MainActor in
                self.downloadFinished(id: id, zipURL: nil, error: ModelError.badResponse(code).localizedDescription)
            }
            return
        }
        // The temp file is deleted when this method returns, so move it now.
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(id)-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            Task { @MainActor in self.downloadFinished(id: id, zipURL: dest, error: nil) }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in self.downloadFinished(id: id, zipURL: nil, error: message) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        let message = error.localizedDescription
        Task { @MainActor in self.downloadFinished(id: id, zipURL: nil, error: message) }
    }
}
