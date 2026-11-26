import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

/// Analyse locale. Ni le prix, ni une marque, ni une taille ne sont déduits d'une photo.
struct BoutiquePhotoDraft: Sendable {
    let original: Data
    let preview: Data
    let studio: Data?
    let suggestion: String?
    let color: String?
}

enum BoutiquePhotoFault: LocalizedError {
    case unreadable, tooLarge, encoding, existing
    var errorDescription: String? {
        switch self {
        case .unreadable: "Cette image ne peut pas être lue."
        case .tooLarge: "La photo dépasse 30 Mo. Choisissez une image plus petite."
        case .encoding: "Impossible de préparer la photo."
        case .existing: "Une photo existe déjà pour cet article."
        }
    }
}

enum BoutiquePhotoProcessor {
    static func suggestedName(identifier: String, confidence: Float) -> String? {
        guard confidence >= 0.45 else { return nil }
        let names: [String: String] = [
            "shirt": "Chemise", "dress shirt": "Chemise", "t-shirt": "T-shirt",
            "tee shirt": "T-shirt", "blouse": "Chemisier", "dress": "Robe",
            "skirt": "Jupe", "trousers": "Pantalon", "pants": "Pantalon",
            "jeans": "Jean", "sweater": "Pull", "cardigan": "Gilet",
            "jacket": "Veste", "coat": "Manteau", "suit": "Costume",
            "shoe": "Chaussure", "sneaker": "Basket", "handbag": "Sac à main",
            "backpack": "Sac à dos", "hat": "Chapeau", "belt": "Ceinture",
            "scarf": "Écharpe", "toy": "Jouet"
        ]
        for label in identifier.lowercased().split(separator: ",") {
            if let name = names[label.trimmingCharacters(in: .whitespacesAndNewlines)] { return name }
        }
        return nil
    }

    static func colorName(red r: Double, green g: Double, blue b: Double) -> String {
        let maxValue = max(r, max(g, b)), minValue = min(r, min(g, b))
        let delta = maxValue - minValue
        if maxValue < 0.16 { return "Noir" }
        if delta < 0.09 { return maxValue > 0.88 ? "Blanc" : "Gris" }
        if maxValue > 0.68 && r > g && g > b && delta < 0.28 { return "Beige" }
        var hue: Double
        if maxValue == r { hue = (g - b) / delta }
        else if maxValue == g { hue = 2 + (b - r) / delta }
        else { hue = 4 + (r - g) / delta }
        hue *= 60
        if hue < 0 { hue += 360 }
        switch hue {
        case 0..<16, 345...360: return "Rouge"
        case 16..<45: return maxValue < 0.6 ? "Marron" : "Orange"
        case 45..<68: return "Jaune"
        case 68..<165: return "Vert"
        case 165..<255: return "Bleu"
        case 255..<290: return "Violet"
        default: return "Rose"
        }
    }

    /// Uniquement le premier plan; une image multicolore ou un masque incertain ne donne pas de couleur.
    private static func dominantColor(_ image: CGImage) -> String? {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                    CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var counts: [String: Int] = [:]
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] >= 245 {
            let color = colorName(red: Double(pixels[index]) / 255,
                green: Double(pixels[index + 1]) / 255, blue: Double(pixels[index + 2]) / 255)
            counts[color, default: 0] += 1; count += 1
        }
        guard count >= 32, let best = counts.max(by: { $0.value < $1.value }),
              Double(best.value) / Double(count) >= 0.60 else { return nil }
        return best.key
    }

    static func process(_ data: Data) throws -> BoutiquePhotoDraft {
        guard data.count <= 30 * 1024 * 1024 else { throw BoutiquePhotoFault.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary),
              let preview = UIImage(cgImage: cg).jpegData(compressionQuality: 0.88)
        else { throw BoutiquePhotoFault.unreadable }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let classifier = VNClassifyImageRequest()
        var name: String?
        if (try? handler.perform([classifier])) != nil {
            name = classifier.results?.prefix(5).compactMap {
                suggestedName(identifier: $0.identifier, confidence: $0.confidence)
            }.first
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        var studio: Data?
        var color: String?
        // Si le détourage échoue, conserver la photo réelle, sans inventer un résultat.
        if (try? handler.perform([request])) != nil,
           let foreground = request.results?.first, !foreground.allInstances.isEmpty,
           let cutout = try? foreground.generateMaskedImage(
              ofInstances: foreground.allInstances, from: handler, croppedToInstancesExtent: true) {
            let image = CIImage(cvPixelBuffer: cutout)
            let context = CIContext()
            if let isolated = context.createCGImage(image, from: image.extent) {
                color = dominantColor(isolated)
            }
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.brightness = 0.015
            if let rendered = context.createCGImage(controls.outputImage ?? image, from: image.extent) {
                let canvas = CGSize(width: cg.width, height: cg.height)
                studio = signedImage(rendered, canvas: canvas)
            }
        }
        return BoutiquePhotoDraft(original: data, preview: preview, studio: studio,
                                   suggestion: name, color: color)
    }

    static func studioFrame(subject: CGSize, canvas: CGSize) -> CGRect {
        let scale = min(1, 0.9 * min(canvas.width / subject.width, canvas.height / subject.height))
        let width = subject.width * scale
        let height = subject.height * scale
        return CGRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2,
                      width: width, height: height)
    }

    private static func signedImage(_ image: CGImage, canvas: CGSize) -> Data? {
        let width = canvas.width
        let height = canvas.height
        let margin = max(32, width * 0.055)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: width, height: height + margin),
                                                format: format).image { renderer in
            UIColor(red: 0.96, green: 0.92, blue: 0.86, alpha: 1).setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: width, height: height + margin))
            let subject = CGSize(width: image.width, height: image.height)
            UIImage(cgImage: image).draw(in: studioFrame(subject: subject, canvas: canvas))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(14, width * 0.023), weight: .medium),
                .foregroundColor: UIColor(red: 0.20, green: 0.25, blue: 0.29, alpha: 1)
            ]
            let label = NSAttributedString(string: "by COVI", attributes: attributes)
            let size = label.size()
            label.draw(at: CGPoint(x: width - size.width - margin * 0.45,
                                   y: height + (margin - size.height) / 2))
        }
        return rendered.jpegData(compressionQuality: 0.90)
    }
}

/// Média local, isolé par établissement et article; aucun changement du schéma SwiftData.
/// La copie originale importée reste intacte. Les captures caméra sont des JPEG de capture.
enum BoutiquePhotoStore {
    static func directory(shopID: UUID, itemID: UUID, root: URL? = nil) throws -> URL {
        let base: URL
        if let root { base = root }
        else { base = try FileManager.default.url(for: .applicationSupportDirectory,
                       in: .userDomainMask, appropriateFor: nil, create: true)
                       .appendingPathComponent("COVIBoutiquePhotos", isDirectory: true) }
        return base.appendingPathComponent(shopID.uuidString, isDirectory: true)
            .appendingPathComponent(itemID.uuidString, isDirectory: true)
    }

    static func save(_ draft: BoutiquePhotoDraft, description: String, shopID: UUID,
                     itemID: UUID, root: URL? = nil) throws {
        let fm = FileManager.default
        let final = try directory(shopID: shopID, itemID: itemID, root: root)
        var parent = final.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        var properties = URLResourceValues()
        properties.isExcludedFromBackup = true
        try parent.setResourceValues(properties)
        guard !fm.fileExists(atPath: final.path) else { throw BoutiquePhotoFault.existing }
        let stage = parent.appendingPathComponent(".stage-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false,
                               attributes: [.protectionKey: FileProtectionType.complete])
        do {
            try draft.original.write(to: stage.appendingPathComponent("original"), options: [.atomic, .completeFileProtection])
            try draft.preview.write(to: stage.appendingPathComponent("preview.jpg"), options: [.atomic, .completeFileProtection])
            if let studio = draft.studio {
                try studio.write(to: stage.appendingPathComponent("studio.jpg"), options: [.atomic, .completeFileProtection])
            }
            try Data(description.utf8).write(to: stage.appendingPathComponent("description.txt"), options: [.atomic, .completeFileProtection])
            try fm.moveItem(at: stage, to: final)
        } catch {
            try? fm.removeItem(at: stage)
            throw error
        }
    }

    static func data(shopID: UUID, itemID: UUID, studio: Bool = false, root: URL? = nil) -> Data? {
        guard let folder = try? directory(shopID: shopID, itemID: itemID, root: root) else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent(studio ? "studio.jpg" : "preview.jpg"))
    }

    static func description(shopID: UUID, itemID: UUID) -> String? {
        guard let folder = try? directory(shopID: shopID, itemID: itemID) else { return nil }
        return try? String(contentsOf: folder.appendingPathComponent("description.txt"), encoding: .utf8)
    }

    static func remove(shopID: UUID, itemID: UUID, root: URL? = nil) throws {
        let folder = try directory(shopID: shopID, itemID: itemID, root: root)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
}

enum BoutiquePhotoSearch {
    static func matches(photo: Data, shopID: UUID, itemIDs: [UUID]) throws -> [UUID] {
        let query = try featurePrint(photo)
        var distances: [(id: UUID, distance: Float)] = []
        for itemID in itemIDs {
            try Task.checkCancellation()
            guard let data = BoutiquePhotoStore.data(shopID: shopID, itemID: itemID),
                  let candidate = try? featurePrint(data) else { continue }
            var distance: Float = 0
            try query.computeDistance(&distance, to: candidate)
            if distance.isFinite {
                distances.append((itemID, distance))
            }
        }
        // Apple does not define a universal matching threshold for these distances.
        // Rank candidates for human confirmation, without claiming an identification.
        return distances.sorted {
            if $0.distance == $1.distance { return $0.id.uuidString < $1.id.uuidString }
            return $0.distance < $1.distance
        }.prefix(8).map { $0.id }
    }

    private static func featurePrint(_ data: Data) throws -> VNFeaturePrintObservation {
        guard data.count <= 30 * 1024 * 1024 else { throw BoutiquePhotoFault.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { throw BoutiquePhotoFault.unreadable }
        let request = VNGenerateImageFeaturePrintRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let feature = request.results?.first else { throw BoutiquePhotoFault.unreadable }
        return feature
    }
}

struct BoutiquePhotoInput: View {
    let busy: Bool
    let onPhoto: (Data) -> Void
    @State private var selection: PhotosPickerItem?
    @State private var camera = false
    @State private var loading = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Photographier", systemImage: "camera") {
                    Task { @MainActor in
                        let allowed = await AVCaptureDevice.requestAccess(for: .video)
                        if allowed { camera = true }
                        else { error = "Autorisez la caméra dans les réglages iOS, ou importez une photo." }
                    }
                }
            }
            PhotosPicker(selection: $selection, matching: .images) {
                Label("Choisir une photo", systemImage: "photo.on.rectangle")
            }
            if busy || loading { ProgressView("Analyse de la photo…") }
            if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .disabled(busy || loading)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            loading = true; error = ""
            Task { @MainActor in
                defer { loading = false; selection = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw BoutiquePhotoFault.unreadable
                    }
                    onPhoto(data)
                } catch { self.error = error.localizedDescription }
            }
        }
        .fullScreenCover(isPresented: $camera) {
            BoutiqueCamera { data in
                camera = false
                if let data { onPhoto(data) }
            }
            .ignoresSafeArea()
        }
    }
}

private struct BoutiqueCamera: UIViewControllerRepresentable {
    let completion: (Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Data?) -> Void
        init(completion: @escaping (Data?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.95))
        }
    }
}

struct BoutiquePhotoPreview: View {
    let draft: BoutiquePhotoDraft
    @State private var showingStudio = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if draft.studio != nil {
                Picker("Présentation", selection: $showingStudio) {
                    Text("Original").tag(false)
                    Text("Studio COVI").tag(true)
                }
                .pickerStyle(.segmented)
            }
            if let ui = UIImage(data: (showingStudio ? draft.studio : nil) ?? draft.preview) {
                Image(uiImage: ui).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .background(COVITheme.champagne)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(showingStudio && draft.studio != nil ? "Photo traitée par Studio COVI" : "Photo originale")
            }
            if let studio = draft.studio, let ui = UIImage(data: studio) {
                let image = Image(uiImage: ui)
                ShareLink(item: image, preview: SharePreview("Studio COVI", image: image)) {
                    Label("Partager la photo Studio", systemImage: "square.and.arrow.up")
                }
            } else {
                Text("Détourage indisponible pour cette image. La photo originale est conservée.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct BoutiqueProductThumbnail: View {
    let shopID: UUID
    let itemID: UUID
    @State private var data: Data?
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "bag").font(.title2).foregroundStyle(COVITheme.navy)
            }
        }
        .frame(width: 65, height: 70)
        .background(COVITheme.champagne)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .accessibilityHidden(true)
        .task(id: itemID) {
            data = await Task.detached(priority: .utility) {
                BoutiquePhotoStore.data(shopID: shopID, itemID: itemID)
            }.value
        }
    }
}
