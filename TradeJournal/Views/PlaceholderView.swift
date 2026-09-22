import SwiftUI

/// Herbruikbare placeholder voor tabs die nog niet zijn geïmplementeerd.
/// Wordt in latere fases vervangen door de echte schermen.
struct PlaceholderView: View {

    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    Image(systemName: systemImage)
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(Theme.accent)

                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(24)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .padding(.horizontal, 24)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    PlaceholderView(
        title: "Dashboard",
        systemImage: "chart.line.uptrend.xyaxis",
        subtitle: "Wordt uitgebouwd in een latere fase."
    )
    .preferredColorScheme(.dark)
}
