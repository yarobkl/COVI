import SwiftUI
import SwiftData

/// Chaque salon crée sa propre équipe. Aucun collaborateur fictif n'est injecté.
struct SalonTeamSettings: View {
    let shop: Establishment
    let actor: UUID
    @Environment(\.modelContext) private var db
    @Query private var team: [SalonStaff]
    @State private var name = ""
    @State private var message = ""

    init(shop: Establishment, actor: UUID) {
        self.shop = shop
        self.actor = actor
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
                        save(kind: "salon.team.availability-changed", entityID: person.id)
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
        .scrollContentBackground(.hidden)
        .background(COVITheme.cream)
    }

    private func add() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(cleaned.count),
              !team.contains(where: { $0.name.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
        else { message = "Choisissez un nom unique de 2 à 80 caractères."; return }
        let member = SalonStaff(shop: shop.id, name: cleaned)
        db.insert(member)
        do {
            try BusinessOutbox.enqueue(kind: "salon.team.created",
                establishmentID: shop.id, entityID: member.id, actorID: actor, in: db)
            try db.save(); name = ""; message = ""
        }
        catch { db.rollback(); message = "Impossible d'enregistrer le collaborateur." }
    }

    private func save(kind: String, entityID: UUID) {
        do {
            try BusinessOutbox.enqueue(kind: kind, establishmentID: shop.id,
                                       entityID: entityID, actorID: actor, in: db)
            try db.save(); message = ""
        }
        catch { db.rollback(); message = "Modification impossible. Réessayez." }
    }
}
