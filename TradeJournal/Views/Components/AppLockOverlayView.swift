import SwiftUI

/// Vergrendelscherm over de hele app zolang het app-slot actief is.
struct AppLockOverlayView: View {

    let viewModel: AppLockViewModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                Text("TradeJournal is vergrendeld")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await viewModel.unlock() }
                } label: {
                    Label("Ontgrendel met \(viewModel.methodName)", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .foregroundStyle(Theme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                }
                .disabled(viewModel.isAuthenticating)
            }
            .padding(Theme.cardPadding)
        }
        // Ligt buiten `RootTabView`; tint hier zetten zodat hij het thema live volgt.
        .tint(Theme.accent)
    }
}
