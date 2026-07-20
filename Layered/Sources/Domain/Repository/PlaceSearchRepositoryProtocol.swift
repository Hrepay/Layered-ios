import Foundation

protocol PlaceSearchRepositoryProtocol {
    /// 키워드·카테고리로 장소 검색.
    /// - Parameters:
    ///   - query: 검색어. 비어 있으면 카테고리 기반 검색 (좌표 필요).
    ///   - category: 필터 칩.
    ///   - latitude/longitude: 검색 중심 좌표. 있으면 거리순 정렬 + 거리 표시.
    func searchPlaces(
        query: String,
        category: PlaceSearchCategory,
        latitude: Double?,
        longitude: Double?
    ) async throws -> [PlaceResult]
}
