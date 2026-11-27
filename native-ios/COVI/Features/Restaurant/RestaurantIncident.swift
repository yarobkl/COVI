import SwiftData
import SwiftUI

@Model final class RestaurantIncident {
    @Attribute(.unique) var lineID: UUID
    var establishmentID: UUID
    var orderID: UUID
    var actorID: UUID
    var tableLabel: String
    var dishName: String
    var reason: String
    var recordedAt: Date

    init(line: OrderLine, table: DiningTable, actorID: UUID, reason: String) {
        lineID = line.id
        establishmentID = table.establishmentID
        orderID = line.orderID
        self.actorID = actorID
        tableLabel = table.label
        dishName = line.dishName ?? "Article"
        self.reason = reason
        recordedAt = .now
    }
}

extension RestaurantService {
    func recordIncident(lineID: UUID, table: DiningTable, order: CommerceOrder, reason: String) throws {
        try authorize()
        guard admin else { throw RestaurantFault.access }
        try check(table, order)
        guard table.isOccupied,
              let line = try db.fetch(FetchDescriptor<OrderLine>(predicate: #Predicate {
                  $0.id == lineID
              })).first,
              line.orderID == order.id, line.preparation == Prep.served.rawValue else {
            throw RestaurantFault.stale
        }
        let cleaned = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...240).contains(cleaned.count) else { throw RestaurantFault.incidentReason }
        guard try db.fetchCount(FetchDescriptor<RestaurantIncident>(predicate: #Predicate {
            $0.lineID == lineID
        })) == 0 else { throw RestaurantFault.incidentExists }

        db.insert(RestaurantIncident(line: line, table: table, actorID: actor, reason: cleaned))
        try save()
    }
}

struct RestaurantIncidentEditor: View {
    let line: OrderLine
    let table: DiningTable
    let order: CommerceOrder
    let service: RestaurantService
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var error = ""
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                COVIBadge(title: service.role == .owner ? "Accès propriétaire" : "Accès responsable",
                          tint: COVITheme.warningTint, foreground: COVITheme.navy)
                Text("Déclarer un incident")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                COVICard {
                    Label {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(line.quantity) × \(line.dishName ?? "Article")").font(.headline)
                            let (amount, overflow) = line.unitPriceMinor.multipliedReportingOverflow(by: Int64(line.quantity))
                            if !overflow && amount > 0 {
                                Text(COVIMoney.text(amount, currency: service.shop.currencyCode)).font(.subheadline)
                            }
                            Text("Déjà servi").font(.caption).foregroundStyle(COVITheme.secondaryText)
                        }
                    } icon: {
                        Image(systemName: "fork.knife")
                            .frame(width: 43, height: 43)
                            .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityHidden(true)
                    }
                }
                COVISectionTitle("Motif et action")
                COVICard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Motif obligatoire").font(.subheadline.bold())
                        TextField("Ex. Plat servi froid", text: $reason, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityLabel("Motif obligatoire")
                            .textFieldStyle(.roundedBorder)
                        Divider()
                        Label("Consigner au rapport de service", systemImage: "doc.text")
                            .font(.subheadline)
                    }
                }
                Label("Enregistrement local sur cet appareil.", systemImage: "info.circle")
                    .font(.subheadline)
                if !error.isEmpty {
                    Text(error).foregroundStyle(.red)
                }
            }
            .padding(COVITheme.Metrics.screenPadding)
        }
        .foregroundStyle(COVITheme.navy)
        .background(COVIBackdrop())
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            COVIButton("Enregistrer l’incident", systemImage: "checkmark") {
                do {
                    try service.recordIncident(lineID: line.id, table: table, order: order, reason: reason)
                    HapticService.confirm()
                    dismiss()
                } catch let failure {
                    error = failure.localizedDescription
                    HapticService.error()
                }
            }
            .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, COVITheme.Metrics.screenPadding)
            .padding(.vertical, 8)
            .background(COVITheme.cream)
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, diagnostics.scenario == .restaurantIncident {
                reason = "Plat servi froid · Retour client"
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }
}
