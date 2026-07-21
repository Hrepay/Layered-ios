import SwiftUI
import MapKit

/// 장소 검색 결과 지도 보기 — 핀 + 하단 요약 카드.
/// 상태(선택·카메라)는 부모(PlaceSearchView)가 소유하고, 동작은 콜백으로 위임.
struct PlaceMapResults: View {
    let places: [PlaceResult]
    /// 가족 추천 모드 — 핀을 하트로 표시하고 카드의 ♥︎ 버튼은 숨김.
    let wishMode: Bool
    @Binding var selection: PlaceResult?
    @Binding var cameraPosition: MapCameraPosition

    let isWished: (PlaceResult) -> Bool
    let onWish: (PlaceResult) -> Void
    let onDetail: (PlaceResult) -> Void
    /// 선택 모드(모임 장소·후보 고르기)일 때만 non-nil — 카드에 "선택" 버튼 노출.
    var onSelect: ((PlaceResult) -> Void)?

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            ForEach(places) { place in
                // 기본 애플 POI를 지우고(아래 mapStyle) 이름 라벨을 노출해 핀 식별성 확보
                Annotation(place.name, coordinate: place.coordinate) {
                    Button {
                        Haptic.light()
                        selection = place
                    } label: {
                        let isSelected = selection?.id == place.id
                        Image(systemName: wishMode ? "heart.fill" : "fork.knife")
                            .font(isSelected ? .body : .subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: isSelected ? 40 : 32, height: isSelected ? 40 : 32)
                            .background(Circle().fill(AppColors.primary))
                            .overlay(Circle().stroke(.white, lineWidth: 2.5))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                }
            }
        }
        // 애플 지도 자체 음식점 아이콘이 핀과 비슷한 색이라 섞여 보임 — 전부 제거해 우리 핀만 표시
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .overlay(alignment: .bottom) {
            if let selected = selection {
                mapCard(selected)
            }
        }
    }

    /// 핀 선택 시 하단에 뜨는 요약 카드.
    private func mapCard(_ place: PlaceResult) -> some View {
        HStack(spacing: 12) {
            PlaceThumbnailView(urlString: place.detailURL, placeName: place.name)

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(place.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let distance = place.distanceText {
                    Text(distance)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if !wishMode {
                Button {
                    guard !isWished(place) else { return }
                    Haptic.medium()
                    onWish(place)
                } label: {
                    Image(systemName: isWished(place) ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(AppColors.primary)
                }
                .buttonStyle(.borderless)
            }

            Button {
                Haptic.light()
                onDetail(place)
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.info)
            }
            .buttonStyle(.borderless)

            if let onSelect {
                Button {
                    Haptic.light()
                    onSelect(place)
                } label: {
                    Text("선택")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppColors.primary))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.light()
            onDetail(place)
        }
    }
}
