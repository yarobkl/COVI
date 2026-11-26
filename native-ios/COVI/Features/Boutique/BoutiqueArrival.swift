import SwiftUI
import UIKit
import SwiftData
import PhotosUI
import AVFoundation
import ImageIO

enum BoutiqueArrivalOrigin: String, CaseIterable, Identifiable {
    case bale, supplier, local, individual

    var id: Self { self }
    var title: String {
        switch self {
        case .bale: "Balles de friperie"
        case .supplier: "Fournisseurs et importations"
        case .local: "Créations locales et couturiers"
        case .individual: "Articles individuels"
        }
    }
}

struct BoutiqueArrivalPhoto: Identifiable {
    let id: UUID
    let url: URL

    private struct Analysis: Codable {
        let preview: Data
        let studio: Data?
        let suggestion: String?
        let color: String?
    }

    private var analysisURL: URL { url.appendingPathExtension("analysis") }

    func preparedDraft() throws -> BoutiquePhotoDraft {
        let original = try Data(contentsOf: url)
        if let data = try? Data(contentsOf: analysisURL),
           let cached = try? PropertyListDecoder().decode(Analysis.self, from: data) {
            return BoutiquePhotoDraft(original: original, preview: cached.preview, studio: cached.studio,
                                      suggestion: cached.suggestion, color: cached.color)
        }
        try Task.checkCancellation()
        let result = try BoutiquePhotoProcessor.process(original)
        try Task.checkCancellation()
        let cached = Analysis(preview: result.preview, studio: result.studio,
                              suggestion: result.suggestion, color: result.color)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(cached).write(to: analysisURL, options: [.atomic, .completeFileProtection])
        return result
    }

    func remove() throws {
        try FileManager.default.removeItem(at: url)
        if FileManager.default.fileExists(atPath: analysisURL.path) {
            try FileManager.default.removeItem(at: analysisURL)
        }
    }
}

struct BoutiqueArrivalStore {
    let shopID: UUID
    let origin: BoutiqueArrivalOrigin
    var root: URL? = nil

    private func directory() throws -> URL {
        let base = try root ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("COVIBoutiqueArrivals", isDirectory: true)
        return base.appendingPathComponent(shopID.uuidString, isDirectory: true)
            .appendingPathComponent(origin.rawValue, isDirectory: true)
    }

    func save(_ data: Data) throws {
        guard data.count <= 30 * 1024 * 1024 else { throw BoutiquePhotoFault.tooLarge }
        guard let image = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(image) > 0 else { throw BoutiquePhotoFault.unreadable }
        var folder = try directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        var properties = URLResourceValues()
        properties.isExcludedFromBackup = true
        try folder.setResourceValues(properties)
        try data.write(to: folder.appendingPathComponent(UUID().uuidString),
                       options: [.atomic, .completeFileProtection])
    }

    func pending() throws -> [BoutiqueArrivalPhoto] {
        let folder = try directory()
        do {
            let files = try FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
            return files.compactMap { url -> (BoutiqueArrivalPhoto, Date)? in
                guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                return (BoutiqueArrivalPhoto(id: id, url: url), date ?? .distantPast)
            }.sorted {
                if $0.1 == $1.1 { return $0.0.id.uuidString < $1.0.id.uuidString }
                return $0.1 < $1.1
            }.map { $0.0 }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }
}

@MainActor
struct BoutiqueArrivals: View {
    let shop: Establishment
    let actor: UUID
    let goods: [CatalogItem]
    @Query private var memberships: [Membership]

    var body: some View {
        List {
            if canReceive {
                Section("Arrivages photo") {
                    ForEach(BoutiqueArrivalOrigin.allCases) { origin in
                        NavigationLink(origin.title) {
                            BoutiqueArrivalQueue(shop: shop, actor: actor, origin: origin)
                        }
                    }
                }
                NavigationLink("Historique et stock des balles") {
                    BaleList(shop: shop, actor: actor, goods: goods)
                }
            } else {
                ContentUnavailableView("Accès réservé", systemImage: "lock",
                    description: Text("La réception des arrivages est réservée au propriétaire et au responsable."))
            }
        }
        .navigationTitle("Arrivages")
    }

    private var canReceive: Bool {
        let role = StaffAccess.role(for: actor, in: shop, memberships: memberships)
        return !shop.archived && (role == .owner || role == .manager)
    }
}

@MainActor
private struct BoutiqueArrivalQueue: View {
    let shop: Establishment
    let actor: UUID
    let origin: BoutiqueArrivalOrigin
    @Environment(\.modelContext) private var context
    @State private var photos: [BoutiqueArrivalPhoto] = []
    @State private var capturedCount = 0
    @State private var selection: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var preparation: Task<Void, Never>?
    @State private var preparedCount = 0
    @State private var batchTotal = 0
    @State private var failedCount = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = false
    @State private var error = ""

    private var store: BoutiqueArrivalStore { BoutiqueArrivalStore(shopID: shop.id, origin: origin) }

    var body: some View {
        List {
            Section {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Photographier en série", systemImage: "camera") {
                        Task {
                            guard await AVCaptureDevice.requestAccess(for: .video) else {
                                error = "Autorisez la caméra dans Réglages ou importez vos photos."
                                return
                            }
                            capturedCount = 0
                            camera = true
                        }
                    }
                }
                PhotosPicker(selection: $selection, maxSelectionCount: 450, matching: .images) {
                    Label("Importer des photos", systemImage: "photo.on.rectangle.angled")
                }
                if importing { ProgressView("Importation…") }
                if !error.isEmpty { Text(error).foregroundStyle(COVITheme.warning) }
            }
            .disabled(importing)
            Section {
                if preparation == nil {
                    Button("Préparer les photos avec COVI Studio", systemImage: "sparkles") {
                        prepareBatch()
                    }
                    .disabled(photos.isEmpty || importing)
                } else {
                    ProgressView("\(preparedCount) / \(batchTotal) photo(s) préparée(s)")
                    Button("Suspendre") { preparation?.cancel() }
                }
                Text("Chaque résultat est conservé sur cet appareil. Vous pouvez reprendre la préparation après une interruption.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                ForEach(photos) { photo in
                    NavigationLink {
                        NewProduct(shop: shop, actor: actor, arrival: photo) { refresh() }
                    } label: {
                        HStack {
                            ArrivalThumbnail(url: photo.url)
                            Text("Vérifier l’article")
                        }
                    }
                    .disabled(preparation != nil)
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Retirer", role: .destructive) {
                            do {
                                try BoutiqueInventoryService.checkReceive(shop: shop, actor: actor, context: context)
                                try photo.remove()
                                refresh()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            } header: {
                Text("\(photos.count) capture(s) à vérifier")
            } footer: {
                Text("Les photos restent sur cet appareil. Confirmez le nom, le prix et la quantité de chaque article avant sa mise en stock.")
            }
        }
        .navigationTitle(origin.title)
        .onAppear { refresh() }
        .onDisappear { preparation?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { preparation?.cancel() }
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty, !importing else { return }
            importing = true
            error = ""
            Task {
                defer {
                    selection = []
                    importing = false
                    refresh()
                }
                var failures = 0
                for item in items {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw BoutiquePhotoFault.unreadable
                        }
                        try save(data)
                    } catch {
                        failures += 1
                        self.error = "\(failures) photo(s) non enregistrée(s). \(error.localizedDescription)"
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $camera, onDismiss: refresh) {
            BoutiqueArrivalCamera(count: $capturedCount) { data in
                try save(data)
                capturedCount += 1
            }
        }
    }

    private func prepareBatch() {
        guard preparation == nil else { return }
        let pending = photos
        batchTotal = pending.count
        preparedCount = 0
        failedCount = 0
        error = ""
        preparation = Task { @MainActor in
            defer { preparation = nil }
            for photo in pending {
                if Task.isCancelled { break }
                do {
                    try BoutiqueInventoryService.checkReceive(shop: shop, actor: actor, context: context)
                } catch {
                    self.error = error.localizedDescription
                    break
                }
                let worker = Task.detached(priority: .utility) { try photo.preparedDraft() }
                do {
                    _ = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    preparedCount += 1
                } catch is CancellationError {
                    break
                } catch {
                    failedCount += 1
                    self.error = "\(failedCount) photo(s) à reprendre. \(error.localizedDescription)"
                }
            }
        }
    }

    private func save(_ data: Data) throws {
        try BoutiqueInventoryService.checkReceive(shop: shop, actor: actor, context: context)
        try store.save(data)
    }

    private func refresh() {
        do {
            try BoutiqueInventoryService.checkReceive(shop: shop, actor: actor, context: context)
            let id = shop.id
            let items = try context.fetch(FetchDescriptor<CatalogItem>(predicate: #Predicate {
                $0.establishmentID == id && !$0.isService
            }))
            let registered = Set(items.map(\.id))
            photos = try store.pending().filter { photo in
                guard registered.contains(photo.id) else { return true }
                try? FileManager.default.removeItem(at: photo.url)
                return false
            }
        } catch {
            photos = []
            self.error = error.localizedDescription
        }
    }
}

private struct ArrivalThumbnail: View {
    let url: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFit()
            } else {
                Image(systemName: "photo")
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
        .task(id: url) {
            let image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: 144
                      ] as CFDictionary) else { return nil as CGImage? }
                return image
            }.value
            if !Task.isCancelled { thumbnail = image.map { UIImage(cgImage: $0) } }
        }
    }
}

@MainActor
private struct BoutiqueArrivalCamera: View {
    @Binding var count: Int
    let save: (Data) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""
    @StateObject private var controller = ArrivalCaptureController()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Terminer") { dismiss() }.disabled(controller.capturing)
                Spacer()
                Text("\(count) enregistrée(s)")
            }
            .padding()
            CapturePreview(controller: controller)
                .accessibilityHidden(true)
            if !error.isEmpty {
                Text(error).foregroundStyle(.white).padding(.horizontal)
            }
            Button {
                error = ""
                controller.capture { result in
                    do { try save(result.get()) }
                    catch { self.error = error.localizedDescription }
                }
            } label: {
                Image(systemName: "circle.inset.filled")
                    .font(.system(size: 52))
                    .padding()
            }
            .accessibilityLabel("Prendre une photo")
            .disabled(!controller.ready || controller.capturing)
        }
        .background(.black)
        .foregroundStyle(.white)
        .onAppear {
            controller.start { error = $0.localizedDescription }
        }
        .onDisappear { controller.stop() }
    }
}

private struct CapturePreview: UIViewRepresentable {
    let controller: ArrivalCaptureController

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Surface {
        let surface = Surface()
        surface.preview.videoGravity = .resizeAspectFill
        surface.preview.session = controller.session
        return surface
    }

    func updateUIView(_ uiView: Surface, context: Context) {}
}

private final class ArrivalCaptureController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "app.covi.arrivals.camera")
    private var configured = false
    @Published private(set) var ready = false
    @Published private(set) var capturing = false
    private var completion: ((Result<Data, Error>) -> Void)?
    private var processedPhoto: Result<Data, Error>?

    func start(onError: @escaping (Error) -> Void) {
        queue.async {
            do {
                if !self.configured {
                    try self.configure()
                    self.configured = true
                }
                self.session.startRunning()
                let running = self.session.isRunning
                DispatchQueue.main.async {
                    self.ready = running
                    if !running { onError(CameraFault.unavailable) }
                }
            } catch {
                DispatchQueue.main.async { onError(error) }
            }
        }
    }

    func stop() {
        ready = false
        queue.async { self.session.stopRunning() }
    }

    func capture(_ completion: @escaping (Result<Data, Error>) -> Void) {
        guard ready, !capturing else { return }
        capturing = true
        self.completion = completion
        processedPhoto = nil
        queue.async {
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let result = Result {
            if let error { throw error }
            guard let data = photo.fileDataRepresentation() else { throw BoutiquePhotoFault.encoding }
            return data
        }
        DispatchQueue.main.async { self.processedPhoto = result }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        DispatchQueue.main.async {
            guard let completion = self.completion else { return }
            let result: Result<Data, Error>
            if let error { result = .failure(error) }
            else { result = self.processedPhoto ?? .failure(BoutiquePhotoFault.encoding) }
            completion(result)
            self.completion = nil
            self.processedPhoto = nil
            self.capturing = false
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { throw CameraFault.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CameraFault.unavailable
        }
        session.addInput(input)
        session.addOutput(output)
    }

    enum CameraFault: LocalizedError {
        case unavailable
        var errorDescription: String? { "La caméra arrière est indisponible." }
    }
}
