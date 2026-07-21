import SwiftUI

/// 가족 맛집 리스트 관리 화면 — 가고 싶은 곳 / 다녀온 곳.
/// 스와이프로 다녀옴 처리·복귀·삭제(본인 추천 또는 관리자만).
struct FamilyWishListView: View {
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var detailWish: PlaceWish?

    private var wishlist: [PlaceWish] {
        appState.placeWishes.filter { $0.status == .wishlist }
    }

    private var visited: [PlaceWish] {
        appState.placeWishes.filter { $0.status == .visited }
    }

    private var isAdmin: Bool {
        appState.currentUser?.id == appState.currentFamily?.adminId
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "가족 맛집 리스트", backAction: { dismiss() })

            if appState.placeWishes.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "heart",
                    title: "아직 추천한 곳이 없어요",
                    description: "주변 맛집을 검색하고 ♥︎를 누르면\n가족 모두가 보는 이 리스트에 담겨요"
                )
                Spacer()
            } else {
                List {
                    if !wishlist.isEmpty {
                        Section("가고 싶은 곳") {
                            ForEach(wishlist) { wish in
                                wishRow(wish)
                            }
                        }
                    }
                    if !visited.isEmpty {
                        Section("다녀온 곳") {
                            ForEach(visited) { wish in
                                wishRow(wish)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { await appState.refreshPlaceWishes() }
        .sheet(item: $detailWish) { wish in
            if let urlString = wish.detailURL, let url = URL(string: urlString) {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    private func wishRow(_ wish: PlaceWish) -> some View {
        HStack(spacing: 12) {
            PlaceThumbnailView(urlString: wish.detailURL, placeName: wish.name)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(wish.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if wish.status == .wishlist && wish.isNewThisWeek {
                        BadgeView(text: "NEW", color: AppColors.primary)
                    }
                }
                Text(wish.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(AppColors.primary)
                    Text("\(wish.recommenderName) 추천")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.light()
            detailWish = wish
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if wish.status == .wishlist {
                Button {
                    Haptic.medium()
                    Task { try? await appState.setPlaceWishStatus(wish.id, status: .visited) }
                } label: {
                    Label("다녀옴", systemImage: "checkmark.circle.fill")
                }
                .tint(AppColors.secondary)
            } else {
                Button {
                    Haptic.medium()
                    Task { try? await appState.setPlaceWishStatus(wish.id, status: .wishlist) }
                } label: {
                    Label("또 가고 싶어요", systemImage: "arrow.uturn.left.circle.fill")
                }
                .tint(AppColors.info)
            }
        }
        .swipeActions(edge: .trailing) {
            // 규칙상 삭제는 추천자 본인 또는 관리자만 — UI도 동일하게 제한
            if wish.recommenderId == appState.currentUser?.id || isAdmin {
                Button(role: .destructive) {
                    Haptic.medium()
                    Task { try? await appState.deletePlaceWish(wish.id) }
                } label: {
                    Label("삭제", systemImage: "trash.fill")
                }
            }
        }
    }
}

#Preview {
    FamilyWishListView()
        .environment(AppState())
}
