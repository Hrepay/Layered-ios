import SwiftUI
import CoreLocation

/// 카카오 로컬 기반 장소(맛집) 검색 시트.
/// 검색어 + 카테고리 칩 + "내 주변" 필터 → 선택 시 onSelect로 결과 전달 후 닫힘.
/// 모임 장소·투표 후보 입력에서 공용으로 사용.
struct PlaceSearchSheet: View {
    let onSelect: (PlaceResult) -> Void
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var category: PlaceSearchCategory = .all
    @State private var nearMe = false
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var results: [PlaceResult] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var showLocationDeniedAlert = false
    @State private var locationProvider = CurrentLocationProvider()

    private var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || (nearMe && coordinate != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "장소 검색",
                backAction: { dismiss() },
                trailingText: "검색",
                trailingAction: {
                    Haptic.light()
                    Task { await search() }
                },
                trailingDisabled: !canSearch || isLoading
            )

            VStack(spacing: 12) {
                AppTextField(placeholder: "지역 + 가게 (예: 강남역 파스타)", text: $query)
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await search() } }
                    .padding(.horizontal, 20)

                // 카테고리 칩 + 내 주변
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        nearMeChip
                        ForEach(PlaceSearchCategory.allCases) { item in
                            categoryChip(item)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 12)

            Divider()

            // 결과 영역
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if results.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: hasSearched ? "magnifyingglass" : "fork.knife",
                    title: hasSearched ? "검색 결과가 없어요" : "주변 맛집을 찾아보세요",
                    description: hasSearched
                        ? "다른 검색어나 카테고리로 시도해보세요"
                        : "지역과 가게 이름으로 검색하거나,\n'내 주변'을 켜고 카테고리만 골라도 돼요"
                )
                Spacer()
            } else {
                List(results) { place in
                    Button {
                        Haptic.light()
                        onSelect(place)
                        dismiss()
                    } label: {
                        resultRow(place)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                }
                .listStyle(.plain)
            }
        }
        .alert("위치 권한이 필요해요", isPresented: $showLocationDeniedAlert) {
            Button("취소", role: .cancel) {}
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("'내 주변' 검색을 쓰려면 iOS 설정에서 겹겹의 위치 접근을 허용해주세요.")
        }
    }

    // MARK: - 칩

    private var nearMeChip: some View {
        Button {
            Haptic.light()
            Task { await toggleNearMe() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.caption2)
                Text("내 주변")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(nearMe ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(nearMe ? AppColors.primary : Color(.secondarySystemBackground)))
        }
    }

    private func categoryChip(_ item: PlaceSearchCategory) -> some View {
        let isSelected = category == item
        return Button {
            Haptic.light()
            category = item
            if canSearch {
                Task { await search() }
            }
        } label: {
            Text(item.rawValue)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? AppColors.primary : Color(.secondarySystemBackground)))
        }
    }

    // MARK: - 결과 행

    private func resultRow(_ place: PlaceResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(place.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(place.category)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                Spacer()
                if let distance = place.distanceText {
                    Text(distance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(place.address)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    // MARK: - 동작

    private func toggleNearMe() async {
        if nearMe {
            nearMe = false
            coordinate = nil
            return
        }
        if let location = await locationProvider.requestCurrentLocation() {
            coordinate = location
            nearMe = true
            await search()
        } else {
            showLocationDeniedAlert = locationProvider.isDenied
        }
    }

    private func search() async {
        guard canSearch else { return }
        isLoading = true
        defer {
            isLoading = false
            hasSearched = true
        }
        do {
            results = try await appState.placeSearchRepository.searchPlaces(
                query: query,
                category: category,
                latitude: nearMe ? coordinate?.latitude : nil,
                longitude: nearMe ? coordinate?.longitude : nil
            )
        } catch {
            results = []
        }
    }
}

#Preview {
    PlaceSearchSheet(onSelect: { _ in })
        .environment(AppState())
}
