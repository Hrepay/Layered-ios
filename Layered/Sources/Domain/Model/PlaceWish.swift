import Foundation

/// 가족에게 추천한 장소 ("가족 맛집 리스트"의 항목).
/// 주 단위로 리셋하지 않고 풀(pool)로 쌓이며, 모임에 사용되면 "다녀온 곳"으로 전환된다.
struct PlaceWish: Identifiable, Hashable {
    enum Status: String {
        case wishlist   // 가고 싶은 곳
        case visited    // 다녀온 곳
    }

    let id: String
    /// 카카오 장소 ID — 같은 가게 중복 추천 방지 키.
    let placeId: String
    let name: String
    let category: String
    let address: String
    let latitude: Double
    let longitude: Double
    let detailURL: String?
    let phone: String?
    let recommenderId: String
    let recommenderName: String
    var status: Status
    let createdAt: Date
    var visitedAt: Date?

    /// 이번 주(월요일 시작)에 올라온 추천인지 — 리스트에서 NEW 강조용.
    var isNewThisWeek: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar.isDate(createdAt, equalTo: Date(), toGranularity: .weekOfYear)
    }

    /// 장소 검색 화면의 행/지도에 그대로 재사용하기 위한 변환.
    /// 추천자 이름을 카테고리 라벨에 함께 노출.
    func toPlaceResult() -> PlaceResult {
        PlaceResult(
            id: placeId,
            name: name,
            category: "\(category) · \(recommenderName) 추천",
            address: address,
            distanceMeters: nil,
            phone: phone,
            latitude: latitude,
            longitude: longitude,
            detailURL: detailURL
        )
    }
}
