import SwiftUI

@MainActor @Observable final class AppSession {
    private(set) var accountID: UUID?
    private var generation = UUID()
    private let store = KeychainStore()
    @ObservationIgnored private(set) var accessToken: String?
    enum Failure: Error { case configuration, unauthorized }

    private func request(_ path: String, token: String? = nil, form: [String: String]? = nil) async throws -> Data {
        guard let host = Bundle.main.object(forInfoDictionaryKey: "COVISupabaseURL") as? String,
              let url = URL(string: host + "/auth/v1/" + path), url.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "COVISupabasePublishableKey") as? String
        else { throw Failure.configuration }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let form {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(form)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw Failure.unauthorized }
        return data
    }

    private struct Tokens: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let user: User
        struct User: Decodable { let id: UUID }
    }
    @ObservationIgnored private var expiry: Task<Void, Never>?
    func authenticate(email: String, password: String) async throws {
        try await exchange("password", ["email": email, "password": password])
    }
    func restore() async throws {
        guard let bytes = try store.data(for: "session.refresh"),
              let token = String(data: bytes, encoding: .utf8) else { return }
        try await exchange("refresh_token", ["refresh_token": token])
    }
    private func exchange(_ grant: String, _ form: [String: String]) async throws {
        let attempt = UUID()
        generation = attempt
        let data = try await request("token?grant_type=" + grant, form: form)
        let tokens = try JSONDecoder().decode(Tokens.self, from: data)
        guard generation == attempt else { throw CancellationError() }
        try store.save(Data(tokens.refresh_token.utf8), for: "session.refresh")
        accountID = tokens.user.id
        accessToken = tokens.access_token
        expiry?.cancel()
        expiry = Task {
            do { try await Task.sleep(for: .seconds(max(1, tokens.expires_in - 60))) }
            catch { return }
            guard generation == attempt else { return }
            accountID = nil
            try? await restore()
        }
    }
    func signOut() throws {
        generation = UUID()
        expiry?.cancel()
        accountID = nil
        try store.delete("session.refresh")
        accessToken = nil
    }
}

struct AccountLogin: View {
    @Environment(AppSession.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        Form {
            TextField("Adresse e-mail", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
            SecureField("Mot de passe", text: $password)
            COVIButton("Se connecter") {
                busy = true
                Task {
                    defer { busy = false; password = "" }
                    do { try await session.authenticate(email: email, password: password) }
                    catch { message = "Connexion impossible. Vérifiez votre connexion et vos identifiants." }
                }
            }.disabled(busy)
            if !message.isEmpty { Text(message) }
        }
    }
}
