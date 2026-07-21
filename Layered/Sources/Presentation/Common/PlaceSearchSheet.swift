import SwiftUI
import CoreLocation
import LinkPresentation
import SafariServices

// MARK: - 장소 검색 코어 (시트·주변 탭 공용)

/// 카카오 로컬 기반 장소(맛집) 검색 화면의 공용 코어.
/// - onSelect가 있으면 "선택 모드": 행 탭 = 선택 후 닫힘, ⓘ 버튼 = 인앱 상세.
/// - onSelect가 없으면 "둘러보기 모드": 행 탭 = 인앱 상세(카카오맵 사진·리뷰).
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
    @State private var showLocationDeniedAlert = false
    @State private var detailPlace: PlaceResult?
    @State private var locationProvider = CurrentLocationProvider()

    var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || (nearMe && coordinate != nil)
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
                    resultRow(place)
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                }
                .listStyle(.plain)
            }
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

    /// "맛집만 보기": 인기·언급량이 반영되는 '맛집' 키워드 + 정확도 정렬로 전환.
    /// 내 주변과 함께 켜면 "가까운 순" 대신 "주변에서 유명한 순"으로 나온다.
    private var restaurantsOnlyChip: some View {
        Button {
            Haptic.light()
            restaurantsOnly.toggle()
            if canSearch {
                Task { await search() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                Text("맛집만")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(restaurantsOnly ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(restaurantsOnly ? AppColors.primary : Color(.secondarySystemBackground)))
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
        HStack(spacing: 12) {
            PlaceThumbnailView(urlString: place.detailURL)

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
        isLoading = true
        defer {
            isLoading = false
            hasSearched = true
        }
        do {
            results = try await appState.placeSearchRepository.searchPlaces(
                query: query,
                category: category,
                restaurantsOnly: restaurantsOnly,
                // 동네명 검색 결과가 실측상 대부분 2km 이내라 반경 UI는 제거 — 상한만 유지
                radiusMeters: 20_000,
                latitude: nearMe ? coordinate?.latitude : nil,
                longitude: nearMe ? coordinate?.longitude : nil
            )
        } catch {
            results = []
        }
    }
}

// MARK: - 선택용 시트 래퍼 (모임 장소·후보·투표 선택지 입력에서 사용)

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

// MARK: - 대표 사진 썸네일 (카카오맵 상세페이지 og:image, 메모리 캐시)

struct PlaceThumbnailView: View {
    let urlString: String?
    @State private var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.secondarySystemBackground)
                Image(systemName: "fork.knife")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: urlString) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let urlString, let url = URL(string: urlString) else { return }
        if let cached = Self.cache.object(forKey: urlString as NSString) {
            image = cached
            return
        }
        // 상세페이지의 og:image를 LinkPresentation으로 추출 — 별도 사진 API 없이 대표 사진 확보
        let provider = LPMetadataProvider()
        guard let metadata = try? await provider.startFetchingMetadata(for: url),
              let imageProvider = metadata.imageProvider else { return }
        let loaded: UIImage? = await withCheckedContinuation { continuation in
            imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
        if let loaded {
            Self.cache.setObject(loaded, forKey: urlString as NSString)
            image = loaded
        }
    }
}

// 인앱 브라우저는 TermsAgreementSheet의 SafariView를 재사용.

#Preview {
    PlaceSearchSheet(onSelect: { _ in })
        .environment(AppState())
}
