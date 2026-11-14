import SwiftUI

#Preview("COVI Design System") {
    ZStack {
        COVITheme.cream.ignoresSafeArea()

        VStack(spacing: 16) {
            COVICard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Boutique")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(COVITheme.navy)
                    Text("Gérez vos ventes et votre stock au quotidien.")
                        .foregroundStyle(COVITheme.secondaryText)
                }
            }

            COVIButton("Commencer", systemImage: "arrow.right") { }
            COVIButton("Se connecter", role: .secondary) { }
        }
        .padding(COVITheme.Metrics.screenPadding)
    }
}
