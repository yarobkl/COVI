import SwiftUI
import SwiftData
import UIKit
import PDFKit

@MainActor enum ReceiptPDFExporter {
    static func export(_ receipt: ReceiptSummary) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let margin: CGFloat = 48
        let width = page.width - margin * 2
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let font = UIFont.systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.black, .paragraphStyle: style
        ]
        let data = renderer.pdfData { context in
            var y = margin
            context.beginPage()
            for rawLine in receipt.shareText.components(separatedBy: "\n") {
                let line = (rawLine.isEmpty ? " " : rawLine) as NSString
                let textSize = line.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes,
                    context: nil)
                let height = max(18, ceil(textSize.height) + 3)
                if y + height > page.height - margin {
                    context.beginPage()
                    y = margin
                }
                line.draw(with: CGRect(x: margin, y: y, width: width, height: height),
                          options: [.usesLineFragmentOrigin, .usesFontLeading],
                          attributes: attributes, context: nil)
                y += height + 5
            }
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("COVI-recu-\(receipt.orderID.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        try data.write(to: file, options: .atomic)
        return file
    }
}

/// Rasterizes every PDF page, preserving the exact verified receipt content.
@MainActor enum ReceiptImageExporter {
    static func export(_ receipt: ReceiptSummary) throws -> [URL] {
        let pdfURL = try ReceiptPDFExporter.export(receipt)
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        guard let document = PDFDocument(url: pdfURL), document.pageCount > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var files: [URL] = []
        do {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { throw CocoaError(.fileReadCorruptFile) }
                let bounds = page.bounds(for: .mediaBox)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 2; format.opaque = true
                let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: bounds.size))
                    context.cgContext.translateBy(x: 0, y: bounds.height)
                    context.cgContext.scaleBy(x: 1, y: -1)
                    page.draw(with: .mediaBox, to: context.cgContext)
                }
                guard let bytes = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "COVI-recu-\(receipt.orderID.uuidString)-\(UUID().uuidString)-page-\(index + 1).png")
                try bytes.write(to: file, options: [.atomic, .completeFileProtection])
                files.append(file)
            }
            return files
        } catch {
            for file in files { try? FileManager.default.removeItem(at: file) }
            throw error
        }
    }
}

private struct ReceiptImageShare: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: files, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ReceiptDetail: View {
    let order: CommerceOrder
    let shop: Establishment
    @Query private var lines: [OrderLine]
    @Query private var payments: [PaymentRecord]
    @Query private var items: [CatalogItem]
    @Query private var refunds: [Refund]
    @State private var imageURLs: [URL] = []
    @State private var sharingImages = false
    @State private var pdfURL: URL?
    @State private var pdfError = ""
    private var receipt: Result<ReceiptSummary, Error> {
        Result { try ReceiptBuilder.create(order: order, shop: shop, lines: lines,
                                          products: items, payments: payments, refunds: refunds) }
    }

    init(order: CommerceOrder, shop: Establishment) {
        self.order = order
        self.shop = shop
        let orderID = order.id, shopID = shop.id
        _lines = Query(filter: #Predicate<OrderLine> { $0.orderID == orderID })
        _payments = Query(filter: #Predicate<PaymentRecord> { $0.orderID == orderID })
        _items = Query(filter: #Predicate<CatalogItem> { $0.establishmentID == shopID })
        _refunds = Query(filter: #Predicate<Refund> { $0.establishmentID == shopID })
    }

    var body: some View {
        Group {
            switch receipt {
            case .failure(let error):
                ContentUnavailableView("Reçu indisponible", systemImage: "exclamationmark.triangle",
                                       description: Text(error.localizedDescription))
            case .success(let model):
                List {
                    Section {
                        Text(shop.name).font(.title2.bold())
                        Text(shop.city).foregroundStyle(.secondary)
                        LabeledContent("Commande", value: String(order.id.uuidString.prefix(8)))
                        LabeledContent("Date", value: order.createdAt.formatted(date: .abbreviated,
                                                                               time: .shortened))
                    }
                    Section("Détail des articles") {
                        ForEach(model.lines) { line in
                            LabeledContent("\(line.quantity) × \(line.name)",
                                           value: "\(line.amountMinor) \(model.currencyCode)")
                        }
                    }
                    Section("Total confirmé") {
                        LabeledContent("Sous-total", value: "\(model.subtotalMinor) \(model.currencyCode)")
                        if model.discountMinor > 0 {
                            LabeledContent("Remise", value: "−\(model.discountMinor) \(model.currencyCode)")
                        }
                        LabeledContent("À payer", value: "\(model.totalMinor) \(model.currencyCode)")
                            .font(.headline)
                        LabeledContent("Règlement", value: model.method)
                        LabeledContent("Confirmé le", value: model.confirmedAt.formatted(date: .abbreviated,
                                                                                        time: .shortened))
                    }
                    if model.refundedMinor > 0 {
                        Section("Remboursement enregistré") {
                            Label("Montant rendu au client", systemImage: "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(.orange)
                            LabeledContent("Remboursé", value: "\(model.refundedMinor) \(model.currencyCode)")
                            if let date = model.refundedAt {
                                LabeledContent("Le", value: date.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                    }
                    Section {
                        Button {
                            do {
                                imageURLs = try ReceiptImageExporter.export(model)
                                pdfError = ""; sharingImages = true
                            } catch { pdfError = "Impossible de créer le reçu image : " + error.localizedDescription }
                        } label: {
                            Label("Partager le reçu en image", systemImage: "photo.on.rectangle")
                        }
                        ShareLink(item: model.shareText) {
                            Label("Partager le reçu", systemImage: "square.and.arrow.up")
                        }
                        if let pdfURL {
                            ShareLink(item: pdfURL, preview: SharePreview("Reçu COVI", image: Image(systemName: "doc.richtext"))) {
                                Label("Partager le PDF", systemImage: "doc.text")
                            }
                        } else {
                            Button {
                                do { pdfURL = try ReceiptPDFExporter.export(model); pdfError = "" }
                                catch { pdfError = "Impossible de créer le PDF : " + error.localizedDescription }
                            } label: {
                                Label("Préparer un PDF", systemImage: "doc.badge.plus")
                            }
                        }
                        if !pdfError.isEmpty { Text(pdfError).foregroundStyle(.red) }
                    }
                }
                .scrollContentBackground(.hidden).background(COVITheme.cream)
            }
        }
        .sheet(isPresented: $sharingImages, onDismiss: {
            for file in imageURLs { try? FileManager.default.removeItem(at: file) }
            imageURLs = []
        }) {
            ReceiptImageShare(files: imageURLs)
        }
        .navigationTitle("Reçu")
    }
}
