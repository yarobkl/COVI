import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// Identité entièrement native : aucune dépendance à une API de comptes externe.
/// Le mode local fonctionne sans réseau. Un identifiant Apple produit le même UUID COVI sur chaque appareil.
@MainActor @Observable final class AppSession {
    private struct Identity: Codable {
        let accountID: UUID
        let appleUserID: String?
        let displayName: String
        let email: String
    }

    private let keychain: any SecureStorage
    private let identityKey = "session.native.identity"
    private let localIdentityKey = "session.native.local"
    private(set) var accountID: UUID?
    private(set) var displayName = ""
    private(set) var email = ""
    private(set) var usesAppleAccount = false

    init(keychain: any SecureStorage = KeychainStore()) {
        self.keychain = keychain
    }

    enum Failure: LocalizedError {
        case noLocalAccount, invalidCredential, revokedAppleCredential
        var errorDescription: String? {
            switch self {
            case .noLocalAccount: "Aucun espace local n'a encore été créé sur cet iPhone."
            case .invalidCredential: "Apple n'a pas pu confirmer votre identité. Réessayez."
            case .revokedAppleCredential: "La connexion Apple a expiré. Reconnectez-vous pour continuer."
            }
        }
    }

    func createLocalAccount(name: String, email: String = "") throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.invalidCredential }
        let existing = try storedIdentity(for: localIdentityKey)
        let identity = Identity(accountID: existing?.accountID ?? UUID(), appleUserID: nil,
                                displayName: trimmed, email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        try save(identity, for: localIdentityKey)
        try activate(identity)
    }

    func continueLocally() throws {
        guard let identity = try storedIdentity(for: localIdentityKey) else { throw Failure.noLocalAccount }
        try activate(identity)
    }

    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential) throws {
        guard !credential.user.isEmpty else { throw Failure.invalidCredential }
        let existing = try storedIdentity(for: identityKey)
        let providedName = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let name = providedName ??
            (existing?.appleUserID == credential.user ? existing?.displayName : nil) ?? "Mon espace COVI"
        let email = credential.email ?? (existing?.appleUserID == credential.user ? existing?.email : nil) ?? ""
        let identity = Identity(accountID: Self.accountIdentifier(for: credential.user),
                                appleUserID: credential.user, displayName: name, email: email)
        try activate(identity)
    }

    func restore() async throws {
        guard let identity = try storedIdentity(for: identityKey) else { return }
        if let appleID = identity.appleUserID {
            let state = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Error>) in
                ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleID) { state, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: state) }
                }
            }
            guard state == .authorized else { throw Failure.revokedAppleCredential }
        }
        apply(identity)
    }

    func signOut() throws {
        try keychain.delete(identityKey)
        accountID = nil
        displayName = ""
        email = ""
        usesAppleAccount = false
    }

    func updateDisplayName(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let current = try storedIdentity(for: identityKey) else {
            throw Failure.invalidCredential
        }
        let updated = Identity(accountID: current.accountID,
                               appleUserID: current.appleUserID,
                               displayName: trimmed, email: current.email)
        if current.appleUserID == nil { try save(updated, for: localIdentityKey) }
        try activate(updated)
    }

    private func activate(_ identity: Identity) throws {
        try save(identity, for: identityKey)
        apply(identity)
    }

    private func apply(_ identity: Identity) {
        accountID = identity.accountID
        displayName = identity.displayName
        email = identity.email
        usesAppleAccount = identity.appleUserID != nil
    }

    private func storedIdentity(for key: String) throws -> Identity? {
        guard let bytes = try keychain.data(for: key) else { return nil }
        return try JSONDecoder().decode(Identity.self, from: bytes)
    }

    private func save(_ identity: Identity, for key: String) throws {
        try keychain.save(JSONEncoder().encode(identity), for: key)
    }

    static func accountIdentifier(for appleUserID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("COVI.apple.\(appleUserID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct NativeAppleSignIn: View {
    @Environment(AppSession.self) private var session
    @State private var message = ""

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                        message = AppSession.Failure.invalidCredential.localizedDescription
                        return
                    }
                    do { try session.signInWithApple(credential); HapticService.confirm() }
                    catch { message = error.localizedDescription }
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code != .canceled {
                        message = "Connexion Apple indisponible. Réessayez dans un instant."
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .accessibilityLabel("Se connecter avec Apple")
            if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.red) }
        }
    }
}

struct AccountLogin: View {
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 37
    @Environment(AppSession.self) private var session
    @State private var message = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image("WelcomeMark").resizable().scaledToFit()
                    .frame(width: 155).frame(maxWidth: .infinity)
                    .accessibilityLabel("COVI, Commerce & Vie")
                    .padding(.top, 20)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Se connecter")
                        .font(.system(size: headingSize, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                        .foregroundStyle(COVITheme.navy)
                    Text("Accédez à votre espace COVI et gérez votre commerce en toute simplicité.")
                        .font(.body).foregroundStyle(COVITheme.secondaryText)
                }
                COVICard {
                    VStack(alignment: .leading, spacing: 13) {
                        Label("Votre identité Apple", systemImage: "person.crop.circle")
                            .font(.headline)
                        Text("La connexion Apple retrouve votre identité sur vos appareils iCloud.")
                            .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                    }
                }
                NativeAppleSignIn()
                HStack(spacing: 12) {
                    Rectangle().fill(COVITheme.separator).frame(height: 1)
                    Text("ou continuer sur cet iPhone")
                        .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(COVITheme.separator).frame(height: 1)
                }
                COVIButton("Reprendre mon espace local", role: .secondary) {
                    do { try session.continueLocally() }
                    catch { message = error.localizedDescription }
                }
                Text("Le mode local fonctionne sans Internet, mais ne permet pas de retrouver votre identité sur un autre iPhone.")
                    .font(.footnote).foregroundStyle(COVITheme.secondaryText)
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(COVIBackdrop())
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RegistrationView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 37
    @Environment(AppSession.self) private var session
    @State private var name = ""
    @State private var email = ""
    @State private var message = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image("WelcomeMark").resizable().scaledToFit()
                    .frame(width: 155).frame(maxWidth: .infinity)
                    .accessibilityLabel("COVI, Commerce & Vie")
                    .padding(.top, 20)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Créer un compte")
                        .font(.system(size: headingSize, weight: .bold))
                        .accessibilityAddTraits(.isHeader).foregroundStyle(COVITheme.navy)
                    Text("Rejoignez COVI pour gérer votre commerce, votre équipe et vos opérations au quotidien.")
                        .foregroundStyle(COVITheme.secondaryText)
                }
                COVICard {
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Votre nom", systemImage: "person")
                                .font(.subheadline.weight(.semibold))
                            TextField("Nom et prénom", text: $name)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Adresse e-mail (facultative)", systemImage: "envelope")
                                .font(.subheadline.weight(.semibold))
                            TextField("exemple@commerce.cg", text: $email)
                                .textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                    }
                    .foregroundStyle(COVITheme.navy)
                    .textFieldStyle(.plain)
                }
                COVIButton("Créer mon espace") {
                    do { try session.createLocalAccount(name: name, email: email); HapticService.confirm() }
                    catch { message = error.localizedDescription }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                COVICard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.title2).foregroundStyle(COVITheme.navy)
                            .frame(width: 46, height: 46)
                            .background(COVITheme.champagne, in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Création locale").font(.headline)
                            Text("L’adresse e-mail ne sert pas encore à confirmer un compte. Votre espace local reste sur cet appareil.")
                                .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                        }
                    }
                }
                Text("Ou créer votre identité avec Apple")
                    .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                    .frame(maxWidth: .infinity)
                NativeAppleSignIn()
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(COVIBackdrop())
        .navigationBarTitleDisplayMode(.inline)
    }
}
