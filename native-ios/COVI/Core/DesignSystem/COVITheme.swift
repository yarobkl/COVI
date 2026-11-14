import SwiftUI

enum COVITheme {
    static let navy = Color(red: 13 / 255, green: 27 / 255, blue: 42 / 255)
    static let cream = Color(red: 253 / 255, green: 245 / 255, blue: 234 / 255)
    static let sand = Color(red: 217 / 255, green: 179 / 255, blue: 140 / 255)
    static let card = Color.white
    static let secondaryText = Color(red: 91 / 255, green: 95 / 255, blue: 100 / 255)
    static let separator = Color.black.opacity(0.08)

    enum Metrics {
        static let screenPadding: CGFloat = 20
        static let cardPadding: CGFloat = 16
        static let buttonHeight: CGFloat = 56
        static let cardRadius: CGFloat = 12
        static let buttonRadius: CGFloat = 16
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
