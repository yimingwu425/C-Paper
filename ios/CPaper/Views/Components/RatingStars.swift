import SwiftUI

struct RatingStars: View {
    @Binding var rating: Int
    var maxRating: Int = 5
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxRating, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? .yellow : .secondary)
                    .font(.system(size: size))
                    .onTapGesture { rating = star }
            }
        }
    }
}
