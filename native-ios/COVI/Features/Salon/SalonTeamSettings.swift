import SwiftUI
import SwiftData

/// Chaque salon crée sa propre équipe. Aucun collaborateur fictif n'est injecté.
struct SalonTeamSettings: View {
    let shop: Establishment
    @Environment(\.modelContext) private var db
    @Query private var team: [SalonStaff]
    @State private var name = ""
    @State private var message = ""

    init(shop: Establishment) {
        self.shop = shop
        let id = shop.id
        _team = Query(filter: #Predicate<SalonStaff> { $0.shop == id }, sort: \.name)
    }

    var body: some View {
        Form {
            Section("Ajouter un collaborateur") {
                TextField("Nom ou prénom", text: $name).textContentType(.name)
                Button("Ajouter à l’équipe") { add() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Vous pouvez ajouter autant de professionnels que nécessaire. Aucun abonnement.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Collaborateurs") {
                if team.isEmpty {
                    ContentUnavailableView("Aucun collaborateur", systemImage: "person.2",
                                           description: Text("Ajoutez votre premier professionnel pour ouvrir les rendez-vous."))
                }
                ForEach(team) { person in
                    Toggle(isOn: Binding(get: { person.active }, set: { enabled in
                        person.active = enabled
                        save()
                    })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(person.name)
                            Text(person.active ? "Disponible pour les rendez-vous" : "Inactif · historique conservé")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Text("La désactivation conserve les rendez-vous, commissions et reçus déjà enregistrés.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !message.isEmpty { Text(message).foregroundStyle(.red) }
        }
        .navigationTitle("Équipe du salon")
    }

    private func add() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(cleaned.count),
              !team.contains(where: { $0.name.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
        else { message = "Choisissez un nom unique de 2 à 80 caractères."; return }
        db.insert(SalonStaff(shop: shop.id, name: cleaned))
        do { try db.save(); name = ""; message = "" }
        catch { db.rollback(); message = "Impossible d'enregistrer le collaborateur." }
    }

    private func save() {
        do { try db.save(); message = "" }
        catch { db.rollback(); message = "Modification impossible. Réessayez." }
    }
}
