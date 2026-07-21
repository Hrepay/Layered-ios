import SwiftUI
import LinkPresentation

/// 장소 대표 사진 썸네일 — 카카오맵 상세페이지 og:image를 추출, 실패 시 카카오 이미지 검색 폴백.
/// 메모리 캐시(NSCache) + 실패 URL 기록으로 중복 요청 방지.
struct PlaceThumbnailView: View {
    let urlString: String?
    let placeName: String
    @State private var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()
    /// 추출 실패한 URL — 행이 다시 나타날 때마다 재요청하지 않게 기록.
    nonisolated(unsafe) private static var failedKeys = Set<String>()

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
        // 재사용/선택 전환 시 이전 장소 사진이 남지 않게 항상 비우고 시작
        image = nil
        guard let urlString, let url = URL(string: urlString),
              !Self.failedKeys.contains(urlString) else { return }
        if let cached = Self.cache.object(forKey: urlString as NSString) {
            image = cached
            return
        }
        // 1차: 상세페이지의 og:image(가게 대표 사진)를 LinkPresentation으로 추출
        if let loaded = await ogImage(from: url) {
            Self.cache.setObject(loaded, forKey: urlString as NSString)
            image = loaded
            return
        }
        // 2차 폴백: 대표 사진이 없는 가게는 카카오 이미지 검색의 첫 썸네일
        guard let fallbackURL = await KakaoPlaceSearchRepository.fallbackThumbnailURL(placeName: placeName),
              let (data, _) = try? await URLSession.shared.data(from: fallbackURL),
              let loaded = UIImage(data: data) else {
            Self.failedKeys.insert(urlString)
            return
        }
        Self.cache.setObject(loaded, forKey: urlString as NSString)
        image = loaded
    }

    private func ogImage(from url: URL) async -> UIImage? {
        let provider = LPMetadataProvider()
        guard let metadata = try? await provider.startFetchingMetadata(for: url),
              let imageProvider = metadata.imageProvider else { return nil }
        return await withCheckedContinuation { continuation in
            imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}
