import SwiftUI

/// 1–5 sterren-rating. `rating == 0` betekent "niet beoordeeld". Tikken op de
/// huidige ster zet de rating terug naar 0.
struct StarRatingView: View {

    @Binding var rating: Int
    var maximum: Int = 5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...maximum, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? Theme.warning : Theme.textTertiary)
                    .onTapGesture {
                        rating = (rating == star) ? 0 : star
                    }
            }
        }
    }
}

#Preview {
    StarRatingView(rating: .constant(3))
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
