import SwiftUI

/// "주변" 탭 — 모임 계획과 무관하게 주변 맛집을 둘러보는 독립 화면.
/// 행 탭 시 카카오맵 상세(사진·리뷰·영업시간)가 인앱 브라우저로 열린다.
struct PlaceDiscoverView: View {
    @Environment(AppState.self) private var appState: AppState
    @State private var query = ""
    @State private var showFamilyList = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("주변 맛집")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    Haptic.light()
                    showFamilyList = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.primary)
                        Text("가족 리스트")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AppColors.primarySubtle))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            PlaceSearchView(query: $query)
                .environment(appState)
        }
        .sheet(isPresented: $showFamilyList) {
            FamilyWishListView()
                .environment(appState)
        }
    }
}

#Preview {
    PlaceDiscoverView()
        .environment(AppState())
}
