import SwiftUI

@MainActor
struct PINEntryView: View {
    @Bindable var pinManager: PINManager
    let scope: PINScope
    var shopName: String? = nil
    var staffName: String? = nil
    let onCompletion: (Bool) -> Void
    @Environment(\.dynamicTypeSize) private var textSize
#if DEBUG && targetEnvironment(simulator)
    @Environment(\.coviSimulatorDiagnostics) private var diagnostics
#endif
    @ScaledMetric(relativeTo: .title) private var digitSize: CGFloat = 30
    @State private var entered = ""
    @State private var clock = Date.now

    private var locked: Bool {
        _ = clock // Le déverrouillage doit redevenir possible dès la fin du délai de protection.
        return pinManager.remainingLockout > 0
    }

    private let keys: [[String]] = [
        ["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "delete.left"]
    ]

    private let letters = ["2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL",
                           "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ"]

    var body: some View {
        GeometryReader { geo in
            let keySize = min(76, max(44, (geo.size.width - 64) / 3))
            let keySpacing = min(23, max(8, (geo.size.width - 3 * keySize - 28) / 2))
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        if let shopName, !shopName.isEmpty {
                            Image("WelcomeMark")
                                .resizable().scaledToFit().frame(width: 106)
                                .accessibilityLabel("COVI, Commerce & Vie")
                            Text(shopName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(COVITheme.secondaryText)
                        } else {
                            Image(systemName: "lock.shield")
                                .font(.title)
                                .accessibilityHidden(true)
                        }
                        Text(prompt)
                            .font(.title.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Saisissez votre code personnel à 4 chiffres")
                            .font(.subheadline)
                            .foregroundStyle(COVITheme.secondaryText)
                    }
                    .multilineTextAlignment(.center)

                    HStack(spacing: 22) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index < entered.count ? COVITheme.navy : .clear)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(COVITheme.navy, lineWidth: 2))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("PIN saisi : \(entered.count) chiffres sur 4")

                    if let error = pinManager.lastError {
                        Text(error.localizedDescription)
                            .font(.footnote).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 13) {
                        ForEach(keys.indices, id: \.self) { row in
                            HStack(spacing: keySpacing) {
                                ForEach(keys[row], id: \.self) { key in
                                    if key.isEmpty {
                                        Color.clear.frame(width: keySize, height: keySize)
                                            .accessibilityHidden(true)
                                    } else {
                                        keypadButton(key, size: keySize)
                                    }
                                }
                            }
                        }
                    }

                    Button("Annuler") { onCompletion(false) }
                        .foregroundStyle(COVITheme.blue)
                        .font(.headline)
                        .frame(minHeight: 44)
                }
                .foregroundStyle(COVITheme.navy)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
                .frame(minHeight: geo.size.height, alignment: .center)
            }
        }
        .background(COVIBackdrop())
        .onAppear { HapticService.prepare() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                clock = .now
            }
        }
#if DEBUG && targetEnvironment(simulator)
        .task {
            guard let diagnostics, diagnostics.scenario == .cashierPIN,
                  pinManager === diagnostics.pin,
                  case .cashier(let staffID, let shopID) = scope,
                  staffID == diagnostics.owner, shopID == diagnostics.shop.id else { return }
            entered = "12"
            await diagnostics.signalAfterPresentation()
        }
#endif
    }

    private func keypadButton(_ key: String, size: CGFloat) -> some View {
        Button { press(key) } label: {
            Group {
                if key == "delete.left" {
                    Image(systemName: "delete.left")
                        .font(.system(size: min(digitSize, size * 0.43)))
                } else {
                    VStack(spacing: 1) {
                        Text(key)
                            .font(.system(size: min(digitSize, size * 0.58), weight: .medium, design: .rounded))
                        if let hint = letters[key], !textSize.isAccessibilitySize {
                            Text(hint)
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .foregroundStyle(COVITheme.navy)
            .frame(width: size, height: size)
            .background(.white.opacity(0.92), in: Circle())
            .shadow(color: COVITheme.navy.opacity(0.09), radius: 8, y: 3)
            .contentShape(Circle())
            .opacity(locked ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityLabel(key == "delete.left" ? "Effacer le dernier chiffre" : key)
    }

    private var prompt: String {
        switch scope {
        case .master: "Code PIN propriétaire"
        case .cashier:
            if let staffName, !staffName.isEmpty {
                "Code PIN de \(staffName)"
            } else {
                "Code PIN de la caisse"
            }
        }
    }

    private func press(_ key: String) {
        guard !locked else { return }
        if key == "delete.left" {
            if !entered.isEmpty { entered.removeLast(); HapticService.keyPress() }
        } else if entered.count < 4 {
            entered.append(key)
            HapticService.keyPress()
            if entered.count == 4 { verify() }
        }
    }
    private func verify() {
        guard entered.count == 4, !locked else { return }
        if pinManager.verify(entered, scope: scope) {
            HapticService.confirm(); onCompletion(true)
        } else {
            HapticService.error(); entered = ""
        }
    }
}
