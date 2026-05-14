import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Query(sort: \Favorite.addedAt, order: .reverse) private var favorites: [Favorite]

    var body: some View {
        Group {
            if favorites.isEmpty {
                EmptyStateView(icon: "star", title: "暂无收藏", subtitle: "收藏常用科目，方便快速搜索")
            } else {
                List(favorites) { fav in
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text(fav.subjectCode)
                                .font(.headline)
                            Text(fav.subjectName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("收藏")
    }
}
