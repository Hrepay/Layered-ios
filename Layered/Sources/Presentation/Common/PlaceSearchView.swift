import SwiftUI
import CoreLocation
import MapKit

// MARK: - 장소 검색 코어 (시트·주변 탭 공용)

/// 카카오 로컬 기반 장소(맛집) 검색 화면의 공용 코어.
/// - onSelect가 있으면 "선택 모드": 행 탭 = 선택 후 닫힘, ⓘ 버튼 = 인앱 상세.
/// - onSelect가 없으면 "둘러보기 모드": 행 탭 = 인앱 상세(카카오맵 사진·리뷰).
/// 지도는 PlaceMapResults, 썸네일은 PlaceThumbnailView로 분리.
struct PlaceSearchView: View {
    var onSelect: ((PlaceResult) -> Void)?
    var onDismissAfterSelect: (() -> Void)?

    @Environment(AppState.self) private var appState: AppState

    @Binding var query: String
    @State private var category: PlaceSearchCategory = .all
    @State private var restaurantsOnly = false
    @State private var nearMe = false
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var results: [PlaceResult] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    /// 마지막 검색이 네트워크/서버 오류로 실패했는지 — "결과 없음"과 구분해 표시.
    @State private var searchFailed = false
    @State private var showLocationDeniedAlert = false
    @State private var detailPlace: PlaceResult?
    @State private var locationProvider = CurrentLocationProvider()
    // 지도 보기
    @State private var showMap = false
    @State private var mapSelection: PlaceResult?
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// 검색 결과 대신 가족 맛집 리스트(가고 싶은 곳)를 표시하는 모드.
    @State private var familyWishMode = false

    var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || (nearMe && coordinate != nil)
    }

    /// 화면에 실제 표시되는 목록 — 가족 추천 모드면 위시리스트, 아니면 검색 결과.
    private var displayResults: [PlaceResult] {
        familyWishMode
            ? appState.placeWishes.filter { $0.status == .wishlist }.map { $0.toPlaceResult() }
            : results
    }

    private func isWished(_ place: PlaceResult) -> Bool {
        appState.placeWishes.contains { $0.placeId == place.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    AppTextField(placeholder: "지역 + 가게 (예: 강남역 파스타)", text: $query)
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await search() } }

                    Button {
                        Haptic.light()
                        Task { await search() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(AppColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canSearch || isLoading)
                }
                .padding(.horizontal, 20)

                // 카테고리 칩 + 내 주변
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        familyWishChip
                        mapToggleChip
                        nearMeChip
                        restaurantsOnlyChip
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

            resultsArea
        }
        .sheet(item: $detailPlace) { place in
            if let urlString = place.detailURL, let url = URL(string: urlString) {
                SafariView(url: url)
                    .ignoresSafeArea()
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

    // MARK: - 결과 영역

    @ViewBuilder
    private var resultsArea: some View {
        if isLoading, !familyWishMode {
            Spacer()
            ProgressView()
            Spacer()
        } else if displayResults.isEmpty {
            Spacer()
            emptyState
            Spacer()
        } else if showMap {
            PlaceMapResults(
                places: displayResults,
                wishMode: familyWishMode,
                selection: $mapSelection,
                cameraPosition: $cameraPosition,
                isWished: isWished,
                onWish: { place in
                    Task { _ = try? await appState.addPlaceWish(from: place) }
                },
                onDetail: { detailPlace = $0 },
                onSelect: onSelect.map { select in
                    { place in
                        select(place)
                        onDismissAfterSelect?()
                    }
                }
            )
        } else {
            List(displayResults) { place in
                resultRow(place)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if familyWishMode {
            EmptyStateView(
                icon: "heart.fill",
                title: "아직 가족 추천이 없어요",
                description: "검색 결과에서 ♥︎를 누르면\n가족 모두가 보는 리스트에 담겨요"
            )
        } else if searchFailed {
            // 네트워크 오류를 "결과 없음"으로 오인하지 않게 구분
            EmptyStateView(
                icon: "wifi.exclamationmark",
                title: "검색에 실패했어요",
                description: "네트워크 상태를 확인하고\n다시 시도해주세요"
            )
        } else {
            EmptyStateView(
                icon: hasSearched ? "magnifyingglass" : "fork.knife",
                title: hasSearched ? "검색 결과가 없어요" : "주변 맛집을 찾아보세요",
                description: hasSearched
                    ? "다른 검색어나 카테고리로 시도해보세요"
                    : "지역과 가게 이름으로 검색하거나,\n'내 주변'을 켜고 카테고리만 골라도 돼요"
            )
        }
    }

    // MARK: - 칩

    /// 필터 칩 공통 스타일 — 켜지면 primary 배경 + 흰 콘텐츠.
    private func filterChip(
        icon: String? = nil,
        title: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptic.light()
            action()
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isOn ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(isOn ? AppColors.primary : Color(.secondarySystemBackground)))
        }
    }

    private var nearMeChip: some View {
        filterChip(icon: "location.fill", title: "내 주변", isOn: nearMe) {
            Task { await toggleNearMe() }
        }
    }

    /// 가족 맛집 리스트(가고 싶은 곳)를 결과 자리에 표시 — 모임 장소·후보 선택 시 바로 활용.
    private var familyWishChip: some View {
        let count = appState.placeWishes.filter { $0.status == .wishlist }.count
        return filterChip(
            icon: "heart.fill",
            title: count > 0 ? "가족 추천 \(count)" : "가족 추천",
            isOn: familyWishMode
        ) {
            familyWishMode.toggle()
            if familyWishMode {
                mapSelection = nil
                cameraPosition = .automatic
                Task { await appState.refreshPlaceWishes() }
            }
        }
    }

    /// 리스트 ↔ 지도 보기 전환.
    private var mapToggleChip: some View {
        filterChip(
            icon: showMap ? "list.bullet" : "map.fill",
            title: showMap ? "리스트" : "지도",
            isOn: showMap
        ) {
            showMap.toggle()
        }
    }

    /// "맛집만 보기": 인기·언급량이 반영되는 '맛집' 키워드 + 정확도 정렬로 전환.
    /// 내 주변과 함께 켜면 "가까운 순" 대신 "주변에서 유명한 순"으로 나온다.
    private var restaurantsOnlyChip: some View {
        filterChip(icon: "star.fill", title: "맛집만", isOn: restaurantsOnly) {
            restaurantsOnly.toggle()
            if canSearch {
                Task { await search() }
            }
        }
    }

    private func categoryChip(_ item: PlaceSearchCategory) -> some View {
        filterChip(title: item.rawValue, isOn: category == item) {
            category = item
            if canSearch {
                Task { await search() }
            }
        }
    }

    // MARK: - 결과 행

    private func resultRow(_ place: PlaceResult) -> some View {
        HStack(spacing: 12) {
            PlaceThumbnailView(urlString: place.detailURL, placeName: place.name)

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
                }
                Text(place.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let distance = place.distanceText {
                        Text(distance)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let phone = place.phone {
                        Text(phone)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if !familyWishMode {
                wishButton(place)
            }

            if onSelect != nil {
                // 선택 모드: 상세는 ⓘ로 따로 열람
                Button {
                    Haptic.light()
                    detailPlace = place
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.body)
                        .foregroundStyle(AppColors.info)
                }
                .buttonStyle(.borderless)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.light()
            if let onSelect {
                onSelect(place)
                onDismissAfterSelect?()
            } else {
                detailPlace = place
            }
        }
    }

    /// 가족 리스트에 추천 담기. 이미 담긴 가게는 채워진 하트로 표시(비활성).
    private func wishButton(_ place: PlaceResult) -> some View {
        let wished = isWished(place)
        return Button {
            guard !wished else { return }
            Haptic.medium()
            Task { _ = try? await appState.addPlaceWish(from: place) }
        } label: {
            Image(systemName: wished ? "heart.fill" : "heart")
                .font(.body)
                .foregroundStyle(AppColors.primary)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - 동작

    private func toggleNearMe() async {
        if nearMe {
            nearMe = false
            coordinate = nil
            // 검색어가 남아 있으면 그 조건으로 재검색, 없으면 이전 결과가
            // 칩과 무관하게 남아 혼란을 주므로 초기 상태로 리셋
            if canSearch {
                await search()
            } else {
                results = []
                hasSearched = false
            }
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

    func search() async {
        guard canSearch else { return }
        // 가족 추천 모드에서 검색하면 결과 화면으로 전환 — 위시리스트가 그대로 남아
        // "검색이 안 된다"고 보이는 것 방지
        familyWishMode = false
        isLoading = true
        defer {
            isLoading = false
            hasSearched = true
            // 새 결과에 맞춰 지도 시야·선택 초기화
            mapSelection = nil
            cameraPosition = .automatic
        }
        do {
            results = try await appState.placeSearchRepository.searchPlaces(
                query: query,
                category: category,
                restaurantsOnly: restaurantsOnly,
                latitude: nearMe ? coordinate?.latitude : nil,
                longitude: nearMe ? coordinate?.longitude : nil
            )
            searchFailed = false
        } catch {
            results = []
            searchFailed = true
        }
    }
}

// MARK: - 선택용 시트 래퍼 (모임 장소·후보 입력에서 사용)

struct PlaceSearchSheet: View {
    let onSelect: (PlaceResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "장소 검색", backAction: { dismiss() })
            PlaceSearchView(
                onSelect: onSelect,
                onDismissAfterSelect: { dismiss() },
                query: $query
            )
        }
    }
}

// 인앱 브라우저는 TermsAgreementSheet의 SafariView를 재사용.

#Preview {
    PlaceSearchSheet(onSelect: { _ in })
        .environment(AppState())
}
