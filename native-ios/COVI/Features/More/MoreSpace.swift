import SwiftUI
import SwiftData
import CloudKit
import CoreImage.CIFilterBuiltins

enum SystemAPI {
    static func call(_ path: String, method: String, token: String, body: [String:String]? = nil, prefer: String = "") async throws -> Data {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "COVISupabaseURL") as? String,
              let url = URL(string: base + path), url.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "COVISupabasePublishableKey") as? String else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !prefer.isEmpty { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { req.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        return data
    }
}

@Model final class MaintenanceEntry {
    var actor: UUID
    var shop: UUID
    var action: String
    var date: Date
    init(_ action: String, actor: UUID, shop: UUID) {
        self.action = action; self.actor = actor; self.shop = shop; date = .now
    }
}

struct MoreSpace: View {
    let shop: Establishment
    let actor: UUID
    let role: StaffRole
    let pin: PINManager
    var body: some View {
        List {
            Section("Établissement") {
                Text(shop.name).font(.headline)
                Text(shop.city)
                NavigationLink("Vitrine publique") { ShowcaseView(shop: shop, actor: actor, pin: pin) }
            }
            Section("Liens rapides") {
                NavigationLink("Paramètres système") { SystemSettings(shop: shop, actor: actor, pin: pin) }
                if role == .owner { NavigationLink("Paramètres propriétaire") { OwnerSettings(shop: shop, pinManager: pin) } }
                if shop.kind == .salon && (role == .owner || role == .manager) {
                    NavigationLink("Catalogue et rapports salon") { SalonSpace(shop: shop, tab: .more, actor: actor, role: role, pin: pin) }
                }
            }
        }.navigationTitle("Plus").scrollContentBackground(.hidden).background(COVITheme.cream)
    }
}

@MainActor
struct ShowcaseView: View {
    let shop: Establishment
    let actor: UUID
    let pin: PINManager
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var db
    @State private var link: URL?
    @State private var message = ""
    @State private var pending: Bool?
    @State private var busy = false
    private struct Row: Decodable { let id: UUID }
    var endpoint: String { "/rest/v1/covi_showcases" }
    func publicURL(_ id: UUID) throws -> URL {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "COVIShowcaseURL") as? String,
              var parts = URLComponents(string: base), parts.scheme == "https", parts.host != nil else { throw URLError(.badURL) }
        parts.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        guard let url = parts.url else { throw URLError(.badURL) }
        return url
    }
    var body: some View {
        List {
            Section("Aperçu") { Text(shop.name).font(.title2.bold()); Text(shop.city); Text(shop.kind.rawValue.capitalized); Text(shop.currencyCode) }
            if let link {
                Link("Ouvrir la vitrine", destination: link)
                ShareLink(item: link)
                if let qr = qr(link) { Image(decorative: qr, scale: 1).interpolation(.none).resizable().scaledToFit().padding().background(.white) }
            }
            if actor == shop.ownerID {
                Button(link == nil ? "Publier la vitrine" : "Actualiser la publication") { pending = true }
                if link != nil { Button("Retirer la publication", role: .destructive) { pending = false } }
            }
            if !message.isEmpty { Text(message) }
        }.disabled(busy).navigationTitle("Vitrine publique")
        .task(id: shop.id) {
            guard let token = session.accessToken, actor == shop.ownerID else { return }
            do {
                let data = try await SystemAPI.call(endpoint + "?select=id&shop_id=eq." + shop.id.uuidString, method: "GET", token: token)
                if let row = try JSONDecoder().decode([Row].self, from: data).first { link = try publicURL(row.id) }
            } catch { message = "État de publication indisponible." }
        }
        .sheet(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            PINEntryView(pinManager: pin, scope: .master(ownerID: shop.ownerID)) { ok in
                let choice = pending; pending = nil
                if ok, let choice { busy = true; Task { await publish(choice) } }
            }
        }
    }
    func publish(_ enable: Bool) async {
        defer { busy = false }
        guard session.accountID == shop.ownerID, !shop.archived, let token = session.accessToken else { return }
        do {
            if enable {
                _ = try publicURL(shop.id)
                let body = ["shop_id":shop.id.uuidString,"name":shop.name,"city":shop.city,"kind":shop.kind.rawValue,"currency":shop.currencyCode]
                let data = try await SystemAPI.call(endpoint + "?on_conflict=owner_id,shop_id&select=id", method: "POST", token: token, body: body, prefer: "resolution=merge-duplicates,return=representation")
                guard let row = try JSONDecoder().decode([Row].self, from: data).first else { throw URLError(.cannotParseResponse) }
                link = try publicURL(row.id)
            } else {
                _ = try await SystemAPI.call(endpoint + "?shop_id=eq." + shop.id.uuidString, method: "DELETE", token: token)
                link = nil
            }
            let action = enable ? "Vitrine publiée" : "Publication retirée"
            db.insert(MaintenanceEntry(action, actor: actor, shop: shop.id))
            try db.save(); message = action
        } catch { message = "Vérifiez le serveur et l’état de publication." }
    }
    func qr(_ url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let image = filter.outputImage else { return nil }
        return CIContext().createCGImage(image, from: image.extent)
    }
}
