import SwiftUI

@MainActor
struct PINEntryView: View {
    @Bindable var pinManager: PINManager
    let scope: PINScope
    let onCompletion: (Bool) -> Void
    @FocusState private var focused: Bool
    @State private var entered = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill").font(.system(size: 42)).foregroundStyle(COVITheme.navy)
            VStack(spacing: 8) {
                Text("Accès sécurisé").font(.title2.weight(.bold)).foregroundStyle(COVITheme.navy)
                Text(prompt).foregroundStyle(COVITheme.secondaryText)
            }
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { index in
                    Circle().fill(index < entered.count ? COVITheme.navy : COVITheme.separator).frame(width: 14, height: 14)
                }
            }
            .accessibilityLabel("PIN saisi : \(entered.count) chiffres sur 4")
            if let error = pinManager.lastError {
                Text(error.localizedDescription).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            SecureField("Code PIN", text: $entered).focused($focused)
                .keyboardType(.numberPad).opacity(0.01).frame(height: 1)
                .onChange(of: entered) { _, value in
                    let sanitized = String(value.filter(\.isNumber).prefix(4))
                    if sanitized != value { entered = sanitized }
                    HapticService.keyPress()
                    if sanitized.count == 4 { verify() }
                }
            COVIButton("Déverrouiller", systemImage: "lock.open.fill") { verify() }
                .disabled(entered.count != 4 || pinManager.remainingLockout > 0)
            Button("Annuler") { onCompletion(false) }.foregroundStyle(COVITheme.navy)
        }
        .padding(COVITheme.Metrics.screenPadding).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(COVITheme.cream).onAppear { focused = true; HapticService.prepare() }
    }

    private var prompt: String {
        switch scope {
        case .master: "Confirmez avec votre PIN propriétaire"
        case .cashier: "Saisissez le code PIN de la caisse"
        }
    }
    private func verify() {
        guard entered.count == 4 else { return }
        if pinManager.verify(entered, scope: scope) {
            HapticService.confirm(); onCompletion(true)
        } else {
            HapticService.error(); entered = ""
        }
    }
}
