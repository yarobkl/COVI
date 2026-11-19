import SwiftUI

enum COVITheme {
    // Palette des maquettes COVI validées : bleu nuit, ivoire et champagne.
    static let navy = Color(red: 7 / 255, green: 35 / 255, blue: 52 / 255)
    static let cream = Color(red: 255 / 255, green: 248 / 255, blue: 241 / 255)
    static let sand = Color(red: 230 / 255, green: 184 / 255, blue: 132 / 255)
    static let champagne = Color(red: 255 / 255, green: 232 / 255, blue: 207 / 255)
    static let blue = Color(red: 14 / 255, green: 85 / 255, blue: 176 / 255)
    static let success = Color(red: 22 / 255, green: 138 / 255, blue: 46 / 255)
    static let successTint = Color(red: 219 / 255, green: 249 / 255, blue: 212 / 255)
    static let warning = Color(red: 174 / 255, green: 83 / 255, blue: 12 / 255)
    static let warningTint = Color(red: 255 / 255, green: 230 / 255, blue: 201 / 255)
    static let dangerTint = Color(red: 255 / 255, green: 216 / 255, blue: 215 / 255)
    static let card = Color.white
    static let secondaryText = Color(red: 91 / 255, green: 95 / 255, blue: 100 / 255)
    static let separator = navy.opacity(0.09)

    enum Metrics {
        static let screenPadding: CGFloat = 20
        static let cardPadding: CGFloat = 16
        static let buttonHeight: CGFloat = 56
        static let cardRadius: CGFloat = 20
        static let buttonRadius: CGFloat = 16
    }
}

/// Fond commun de toutes les activités ; les motifs restent décoratifs et ne masquent aucun contrôle.
struct COVIBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                COVITheme.cream
                Ellipse()
                    .fill(COVITheme.champagne.opacity(0.72))
                    .frame(width: geometry.size.width * 1.15, height: 240)
                    .rotationEffect(.degrees(-33))
                    .offset(x: geometry.size.width * 0.43, y: -110)
                Ellipse()
                    .fill(COVITheme.champagne.opacity(0.36))
                    .frame(width: geometry.size.width * 1.35, height: 230)
                    .rotationEffect(.degrees(-23))
                    .offset(x: -geometry.size.width * 0.20, y: geometry.size.height - 100)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct COVISectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(COVITheme.navy)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

enum COVIMoney {
    static func text(_ amount: Int64, currency: String) -> String {
        "\(amount.formatted(.number.grouping(.automatic))) \(currency == "XAF" ? "FCFA" : currency)"
    }
}

struct COVIBadge: View {
    let title: String
    var tint: Color = COVITheme.champagne
    var foreground: Color = COVITheme.navy

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint, in: Capsule())
    }
}

struct COVIIconRow: View {
    let symbol: String
    let title: String
    let detail: String?
    var tint: Color = COVITheme.champagne
    var accessory: String? = "chevron.right"

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(COVITheme.navy)
                .frame(width: 43, height: 43)
                .background(tint, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(COVITheme.navy)
                if let detail { Text(detail).font(.caption).foregroundStyle(COVITheme.secondaryText) }
            }
            Spacer(minLength: 6)
            if let accessory {
                Image(systemName: accessory).font(.subheadline.weight(.semibold))
                    .foregroundStyle(COVITheme.navy)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 48)
    }
}

struct COVICard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(COVITheme.Metrics.cardPadding)
            .background(COVITheme.card, in: RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: COVITheme.Metrics.cardRadius, style: .continuous)
                    .stroke(COVITheme.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

enum COVIButtonRole {
    case primary
    case secondary
    case tertiary
}

struct COVIButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let role: COVIButtonRole
    private let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, role: COVIButtonRole = .primary, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: COVITheme.Metrics.buttonHeight)
        }
        .buttonStyle(COVIButtonStyle(role: role))
        .accessibilityAddTraits(.isButton)
    }
}

private struct COVIButtonStyle: ButtonStyle {
    let role: COVIButtonRole

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: COVITheme.Metrics.buttonRadius, style: .continuous))
            .overlay {
                if role == .secondary {
                    RoundedRectangle(cornerRadius: COVITheme.Metrics.buttonRadius, style: .continuous)
                        .stroke(COVITheme.navy.opacity(0.35), lineWidth: 1.5)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        role == .primary ? .white : COVITheme.navy
    }

    private var backgroundColor: Color {
        switch role {
        case .primary: COVITheme.navy
        case .secondary: COVITheme.cream
        case .tertiary: .clear
        }
    }
}
