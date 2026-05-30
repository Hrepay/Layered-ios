import SwiftUI
import MapKit

// MARK: - 함께 다닌 장소 미니맵

/// 히스토리에 표시할 가족이 다닌 장소들의 미니 지도.
/// `placeLatitude/Longitude`가 있는 모임만 핀으로 표시. 같은 장소명은 첫 번째 좌표로 합쳐 1개 핀.
struct PlacesMiniMap: View {
    let meetings: [Meeting]

    private var places: [(name: String, coordinate: CLLocationCoordinate2D)] {
        var dedup: [String: CLLocationCoordinate2D] = [:]
        var order: [String] = []
        for meeting in meetings {
            guard let lat = meeting.placeLatitude,
                  let lng = meeting.placeLongitude,
                  !meeting.place.isEmpty,
                  dedup[meeting.place] == nil else { continue }
            dedup[meeting.place] = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            order.append(meeting.place)
        }
        return order.map { (name: $0, coordinate: dedup[$0]!) }
    }

    private var region: MKCoordinateRegion {
        guard !places.isEmpty else {
            // 서울 시청 기본
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        let lats = places.map(\.coordinate.latitude)
        let lngs = places.map(\.coordinate.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0
        let maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        // 핀 1개일 땐 적당히 줌, 여러 개면 묶이는 만큼 + 패딩
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.01),
            longitudeDelta: max((maxLng - minLng) * 1.6, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        if places.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.primary)
                    Text("함께 다닌 장소")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(places.count)곳")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Map(initialPosition: .region(region)) {
                    ForEach(places, id: \.name) { place in
                        Marker(place.name, coordinate: place.coordinate)
                            .tint(AppColors.primary)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .allowsHitTesting(false) // 스크롤 충돌 방지 — 핀만 시각화
            }
        }
    }
}

// MARK: - 활동 분포 차트

/// 모임 활동 키워드를 분류해 가로 막대로 표시.
/// HomeView의 activityIcons와 같은 키워드 셋을 공유 — 변경 시 두 곳을 모두 손봐야 함.
/// 기본 접힌 상태로 시작, 헤더 탭하면 부드럽게 펼침.
struct ActivityDistributionChart: View {
    let meetings: [Meeting]
    @State private var isExpanded = false

    private static let keywordIconMap: [(String, String)] = [
        ("외식", "fork.knife"),
        ("카페", "cup.and.saucer.fill"),
        ("영화", "film.fill"),
        ("산책", "figure.walk"),
        ("운동", "figure.run"),
        ("피크닉", "leaf.fill"),
        ("쇼핑", "cart.fill"),
        ("집에서", "house.fill"),
        ("게임", "gamecontroller.fill"),
        ("문화생활", "book.fill"),
    ]

    private var entries: [(label: String, icon: String, count: Int)] {
        var counts: [String: Int] = [:]
        for meeting in meetings {
            guard let activity = meeting.activity else { continue }
            for (keyword, _) in Self.keywordIconMap where activity.contains(keyword) {
                counts[keyword, default: 0] += 1
            }
        }
        let result: [(label: String, icon: String, count: Int)] = Self.keywordIconMap.compactMap { keyword, icon in
            guard let c = counts[keyword], c > 0 else { return nil }
            return (label: keyword, icon: icon, count: c)
        }
        return result.sorted { $0.count > $1.count }
    }

    private var maxCount: Int { entries.map(\.count).max() ?? 0 }

    var body: some View {
        if entries.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 10) {
                // 클릭 가능한 헤더 — chevron 회전으로 펼침 상태 표시
                Button {
                    Haptic.light()
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chart.bar.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppColors.primarySubtle))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("가족이 좋아하는 활동")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("\(entries.count)개 카테고리")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassGroupedBackground()

                if isExpanded {
                    VStack(spacing: 8) {
                        ForEach(entries.prefix(6), id: \.label) { entry in
                            activityRow(entry)
                        }
                    }
                    .card()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                }
            }
        }
    }

    private func activityRow(_ entry: (label: String, icon: String, count: Int)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .font(.caption)
                .foregroundStyle(AppColors.primary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppColors.primarySubtle))

            Text(entry.label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(width: 64, alignment: .leading)

            // 막대
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemGray5))
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(AppColors.primary)
                        .frame(
                            width: maxCount > 0 ? geo.size.width * CGFloat(entry.count) / CGFloat(maxCount) : 0,
                            height: 10
                        )
                }
            }
            .frame(height: 10)

            Text("\(entry.count)회")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
