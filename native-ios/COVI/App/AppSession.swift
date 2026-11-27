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

private struct AccountEntryLayout<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image("WelcomeMark").resizable().scaledToFit()
                    .frame(width: 134).frame(maxWidth: .infinity)
                    .accessibilityLabel("COVI, Commerce & Vie")
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .foregroundStyle(COVITheme.secondaryText)
                }
                content()
            }
            .foregroundStyle(COVITheme.navy)
            .padding(COVITheme.Metrics.screenPadding)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(COVIBackdrop())
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountLogin: View {
    let onRegistration: () -> Void
    @Environment(AppSession.self) private var session
    @State private var message = ""
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

    var body: some View {
        AccountEntryLayout(title: "Se connecter",
            subtitle: "Retrouvez votre espace COVI et les activités de votre commerce.") {
            NativeAppleSignIn()
            COVICard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Votre espace sur cet iPhone", systemImage: "iphone")
                        .font(.headline)
                    Text("Retrouvez un espace déjà créé sur cet iPhone, même sans Internet.")
                        .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                    COVIButton("Reprendre mon espace local", role: .secondary) {
                        do { try session.continueLocally() }
                        catch { message = error.localizedDescription }
                    }
                    if !message.isEmpty {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            VStack(spacing: 3) {
                Text("Vous découvrez COVI ?")
                    .font(.subheadline)
                    .foregroundStyle(COVITheme.secondaryText)
                Button("Créer un compte", action: onRegistration)
                    .font(.headline)
                    .foregroundStyle(COVITheme.blue)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, diagnostics.scenario == .accountLogin {
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }
}

struct RegistrationView: View {
    @Environment(AppSession.self) private var session
    @State private var name = ""
    @State private var email = ""
    @State private var message = ""
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif

    var body: some View {
        let canCreate = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        AccountEntryLayout(title: "Créer un compte",
            subtitle: "Rejoignez COVI pour gérer votre commerce et votre équipe.") {
            NativeAppleSignIn()

            Text("Ou créer un espace sur cet iPhone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(COVITheme.secondaryText)
                .frame(maxWidth: .infinity)

            COVICard {
                VStack(spacing: 13) {
                    registrationField("Votre nom", symbol: "person") {
                        TextField("Votre nom", text: $name, prompt: Text("Nom et prénom"))
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                    }
                    Divider()
                    registrationField("Adresse e-mail (facultative)", symbol: "envelope") {
                        TextField("Adresse e-mail (facultative)", text: $email, prompt: Text("exemple@commerce.cg"))
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }
                .textFieldStyle(.plain)
            }
            COVIButton("Créer mon espace local") {
                do { try session.createLocalAccount(name: name, email: email); HapticService.confirm() }
                catch { message = error.localizedDescription }
            }
            .disabled(!canCreate)
            .opacity(canCreate ? 1 : 0.55)

            Label("Cet espace et ses données restent sur cet iPhone. L’adresse e-mail sert à votre profil local.",
                  systemImage: "iphone")
                .font(.footnote)
                .foregroundStyle(COVITheme.secondaryText)
            if !message.isEmpty { Text(message).foregroundStyle(.red) }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            if let diagnostics, diagnostics.scenario == .accountRegistration {
                await diagnostics.signalAfterPresentation()
            }
        }
#endif
    }

    private func registrationField<Content: View>(_ title: String, symbol: String,
                                                  @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
