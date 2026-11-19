import SwiftUI

@MainActor
struct PINEntryView: View {
    @Bindable var pinManager: PINManager
    let scope: PINScope
    let onCompletion: (Bool) -> Void
    @State private var entered = ""

    private let keys: [[String]] = [
        ["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "delete.left"]
    ]

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.title).foregroundStyle(COVITheme.navy)
                        Text(prompt)
                            .font(.system(size: 29, weight: .bold))
                            .foregroundStyle(COVITheme.navy)
                            .multilineTextAlignment(.center)
                        Text("Saisissez votre code personnel à 4 chiffres")
                            .font(.subheadline).foregroundStyle(COVITheme.secondaryText)
                    }
                    HStack(spacing: 28) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index < entered.count ? COVITheme.navy : .clear)
                                .frame(width: 19, height: 19)
                                .overlay(Circle().stroke(COVITheme.navy, lineWidth: 2))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("PIN saisi : \(entered.count) chiffres sur 4")

                    if let error = pinManager.lastError {
                        Text(error.localizedDescription)
                            .font(.footnote).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 16) {
                        ForEach(keys.indices, id: \.self) { row in
                            HStack(spacing: 30) {
                                ForEach(keys[row], id: \.self) { key in
                                    if key.isEmpty {
                                        Color.clear.frame(width: 75, height: 75)
                                    } else {
                                        Button {
                                            press(key)
                                        } label: {
                                            Group {
                                                if key == "delete.left" {
                                                    Image(systemName: "delete.left")
                                                        .font(.system(size: 29))
                                                } else {
                                                    Text(key)
                                                        .font(.system(size: 38, weight: .medium, design: .rounded))
                                                }
                                            }
                                            .foregroundStyle(COVITheme.navy)
                                            .frame(width: 75, height: 75)
                                            .background(.white.opacity(0.88), in: Circle())
                                            .shadow(color: COVITheme.navy.opacity(0.09), radius: 9, y: 4)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(pinManager.remainingLockout > 0)
                                        .accessibilityLabel(key == "delete.left" ? "Effacer le dernier chiffre" : key)
                                    }
                                }
                            }
                        }
                    }
                    Button("Changer de compte") { onCompletion(false) }
                        .foregroundStyle(COVITheme.blue)
                        .font(.headline)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
            }
        }
        .background(COVIBackdrop())
        .onAppear { HapticService.prepare() }
    }

    private var prompt: String {
        switch scope {
        case .master: "Code PIN propriétaire"
        case .cashier: "Code PIN de la caisse"
        }
    }
    private func press(_ key: String) {
        guard pinManager.remainingLockout <= 0 else { return }
        if key == "delete.left" {
            if !entered.isEmpty { entered.removeLast(); HapticService.keyPress() }
        } else if entered.count < 4 {
            entered.append(key)
            HapticService.keyPress()
            if entered.count == 4 { verify() }
        }
    }
    private func verify() {
        guard entered.count == 4, pinManager.remainingLockout <= 0 else { return }
        if pinManager.verify(entered, scope: scope) {
            HapticService.confirm(); onCompletion(true)
        } else {
            HapticService.error(); entered = ""
        }
    }
}
