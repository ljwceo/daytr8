import SwiftUI

/// Kort laadscherm bij de start van de app, met het woordmerk in de kleuren
/// van het gekozen thema. De statische iOS-launchscreen (Info.plist) toont
/// daarvóór het icoon in de standaardkleuren.
struct SplashView: View {

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Daytr8LogoView(variant: .wordmark, size: 44)
        }
    }
}

#Preview {
    SplashView()
}
