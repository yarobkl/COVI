import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins

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
                NavigationLink("Fiche à partager") { LocalShopCard(shop: shop) }
            }
            Section("Votre espace") {
                NavigationLink("Paramètres système") { SystemSettings(shop: shop, actor: actor, pin: pin) }
                NavigationLink("Historique des reçus") { CommerceReceiptHistory(shop: shop) }
                NavigationLink("Aide et confidentialité") { HelpPrivacyView(kind: shop.kind) }
                if role == .owner {
                    NavigationLink("Paramètres propriétaire") { OwnerSettings(shop: shop, pinManager: pin) }
                }
                if shop.kind == .salon && (role == .owner || role == .manager) {
                    NavigationLink("Catalogue et rapports salon") {
                        SalonSpace(shop: shop, tab: .more, actor: actor, role: role, pin: pin)
                    }
                }
            }
            Section {
                LabeledContent("Abonnement", value: "Gratuit")
                Text("Les données du commerce sont gérées sur iPhone, sans base de données web.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Plus")
        .scrollContentBackground(.hidden)
        .background(COVITheme.cream)
    }
}

struct HelpPrivacyView: View {
    let kind: BusinessKind

    var body: some View {
        List {
            Section("Bien démarrer") {
                Label("1. Ajoutez vos articles, votre carte ou vos prestations.", systemImage: "square.and.pencil")
                Label("2. Enregistrez vos ventes ou rendez-vous sur l’iPhone.", systemImage: "checklist")
                Label("3. Confirmez les paiements lorsque l’argent est réellement reçu en caisse.",
                      systemImage: "checkmark.shield")
            }
            Section("Votre activité") {
                switch kind {
                case .boutique:
                    Text("Utilisez Stock pour créer les produits et suivre les arrivages, puis Vendre pour encaisser.")
                case .restaurant:
                    Text("Configurez les tables et les menus. Le personnel envoie les plats en cuisine et confirme l’addition en caisse.")
                case .salon:
                    Text("Ajoutez d’abord votre équipe et vos prestations depuis Plus, puis créez les fiches clients et les rendez-vous.")
                }
            }
            Section("Paiements") {
                Text("COVI ne retire aucun argent des comptes clients. Espèces et Mobile Money sont enregistrés uniquement après confirmation humaine.")
                Text("Le service est gratuit : aucun abonnement ni achat intégré.")
            }
            Section("Confidentialité") {
                Label("Données locales enregistrées avec SwiftData.", systemImage: "iphone")
                Label("Identité locale enregistrée dans le trousseau sécurisé iOS.", systemImage: "lock")
                Label("Le compte Apple utilise AuthenticationServices.", systemImage: "person.crop.circle")
                Text("Le répertoire des établissements et les reçus confirmés peuvent être synchronisés dans le CloudKit privé de votre compte iCloud. Les stocks, fiches clients et commandes en cours restent sur cet iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Aide et confidentialité")
        .scrollContentBackground(.hidden).background(COVITheme.cream)
    }
}

struct CommerceReceiptHistory: View {
    let shop: Establishment
    @Query private var orders: [CommerceOrder]

    init(shop: Establishment) {
        self.shop = shop
        let id = shop.id
        _orders = Query(filter: #Predicate<CommerceOrder> { $0.establishmentID == id },
                        sort: \.createdAt, order: .reverse)
    }

    var body: some View {
        let completed = orders.filter { $0.state == .completed && $0.totalMinor > 0 }
        List {
            if completed.isEmpty {
                ContentUnavailableView("Aucun reçu", systemImage: "receipt",
                                       description: Text("Les ventes confirmées en caisse apparaîtront ici."))
            }
            ForEach(completed) { order in
                NavigationLink {
                    ReceiptDetail(order: order, shop: shop)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(order.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text("\(order.totalMinor) \(shop.currencyCode) · " +
                             String(order.id.uuidString.prefix(8)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Historique des reçus")
        .scrollContentBackground(.hidden)
        .background(COVITheme.cream)
    }
}

/// Carte de visite hors ligne, partageable sans publication de données sur un serveur.
struct LocalShopCard: View {
    let shop: Establishment
    private var details: String {
        let label: String
        switch shop.kind {
        case .boutique: label = "Boutique"
        case .restaurant: label = "Restaurant"
        case .salon: label = "Salon de coiffure"
        }
        return "\(shop.name)\n\(label) · \(shop.city)\nFiche créée avec COVI"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: shop.kind == .restaurant ? "fork.knife" :
                    shop.kind == .salon ? "scissors" : "bag")
                    .font(.system(size: 44))
                    .foregroundStyle(COVITheme.navy)
                    .accessibilityHidden(true)
                Text(shop.name).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Label(shop.city, systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Text("Cette fiche est accessible hors ligne. Le QR code partage uniquement le nom, l’activité et la ville.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let qr = qrImage {
                    Image(decorative: qr, scale: 1)
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 240).padding(22)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24))
                        .accessibilityLabel("QR code de la fiche \(shop.name)")
                }
                ShareLink(item: details) {
                    Label("Partager la fiche", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(COVITheme.navy)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(COVITheme.cream)
        .navigationTitle("Fiche établissement")
    }

    private var qrImage: CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(details.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return nil }
        return CIContext().createCGImage(image, from: image.extent)
    }
}
