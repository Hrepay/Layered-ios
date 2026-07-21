import Foundation

/// 카카오 로컬 API 기반 장소 검색.
/// - 키워드 검색: https://dapi.kakao.com/v2/local/search/keyword.json
/// - 카테고리 검색: https://dapi.kakao.com/v2/local/search/category.json (검색어 없이 "내 주변 전체" 탐색용)
/// 무료 쿼터(일 10만 건) 내 사용. 초과 시 요청이 거부될 뿐 과금되지 않음.
final class KakaoPlaceSearchRepository: PlaceSearchRepositoryProtocol {
    private let session = URLSession.shared

    func searchPlaces(
        query: String,
        category: PlaceSearchCategory,
        restaurantsOnly: Bool,
        latitude: Double?,
        longitude: Double?
    ) async throws -> [PlaceResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            guard let latitude, let longitude else { return [] }
            // "맛집만"이면 좌표 반경 안에서 '맛집' 키워드 검색 — 카카오 인기도 랭킹 활용
            if restaurantsOnly {
                return try await keywordSearch(
                    query: "", category: category, restaurantsOnly: true,
                    latitude: latitude, longitude: longitude
                )
            }
            // 그 외엔 카테고리 탐색 (음식점/카페 그룹 전체, 거리순)
            return try await categorySearch(category: category, latitude: latitude, longitude: longitude)
        }
        return try await keywordSearch(
            query: trimmed, category: category, restaurantsOnly: restaurantsOnly,
            latitude: latitude, longitude: longitude
        )
    }

    // MARK: - 요청 빌드

    private func keywordSearch(
        query: String,
        category: PlaceSearchCategory,
        restaurantsOnly: Bool,
        latitude: Double?,
        longitude: Double?
    ) async throws -> [PlaceResult] {
        // 세부 업종 칩은 검색어에 접두어로 합성 (카카오는 업종 키워드 검색 품질이 좋음)
        var parts: [String] = []
        switch category {
        case .all, .cafe:
            break
        default:
            parts.append(category.rawValue)
        }
        if !query.isEmpty {
            parts.append(query)
        }
        // "맛집만": 카카오가 인기·언급량 기반으로 랭킹하는 '맛집' 키워드 합성.
        // 카페 칩은 '카페 맛집'이 어색하므로 '카페'로 검색 (인기도 정렬은 동일 적용)
        if restaurantsOnly {
            parts.append(category == .cafe ? "카페" : "맛집")
        }
        let effectiveQuery = parts.joined(separator: " ")
        guard !effectiveQuery.isEmpty else { return [] }

        var items = [
            URLQueryItem(name: "query", value: effectiveQuery),
            URLQueryItem(name: "size", value: "15"),
        ]
        // 카페 칩은 카테고리 그룹으로 정확히 제한, 나머지는 음식점 그룹으로 제한
        switch category {
        case .cafe: items.append(URLQueryItem(name: "category_group_code", value: "CE7"))
        case .all: break
        default: items.append(URLQueryItem(name: "category_group_code", value: "FD6"))
        }
        if let latitude, let longitude {
            // 맛집만: 반경을 좁히고 인기도(정확도) 정렬 — "가까운 순"이 아니라 "주변에서 유명한 순"
            items.append(contentsOf: [
                URLQueryItem(name: "x", value: String(longitude)),
                URLQueryItem(name: "y", value: String(latitude)),
                URLQueryItem(name: "radius", value: restaurantsOnly ? "5000" : "20000"),
                URLQueryItem(name: "sort", value: restaurantsOnly ? "accuracy" : "distance"),
            ])
        }
        return try await request(path: "keyword", queryItems: items)
    }

    private func categorySearch(
        category: PlaceSearchCategory,
        latitude: Double,
        longitude: Double
    ) async throws -> [PlaceResult] {
        let groupCode = (category == .cafe) ? "CE7" : "FD6"
        let items = [
            URLQueryItem(name: "category_group_code", value: groupCode),
            URLQueryItem(name: "x", value: String(longitude)),
            URLQueryItem(name: "y", value: String(latitude)),
            URLQueryItem(name: "radius", value: "2000"),
            URLQueryItem(name: "sort", value: "distance"),
            URLQueryItem(name: "size", value: "15"),
        ]
        let results = try await request(path: "category", queryItems: items)
        // 세부 업종 칩이면 카테고리명으로 클라이언트 필터 (카테고리 API는 그룹 단위까지만 지원)
        guard category != .all, category != .cafe else { return results }
        return results.filter { $0.category.contains(category.rawValue) }
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> [PlaceResult] {
        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/\(path).json")!
        components.queryItems = queryItems
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("KakaoAK \(AppConstants.Kakao.restAPIKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "placeSearch", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "장소 검색에 실패했습니다. 잠시 후 다시 시도해주세요",
            ])
        }
        let decoded = try JSONDecoder().decode(KakaoLocalResponse.self, from: data)
        return decoded.documents.map { $0.toPlaceResult() }
    }
}

// MARK: - 응답 디코딩

private struct KakaoLocalResponse: Decodable {
    let documents: [KakaoPlaceDocument]
}

private struct KakaoPlaceDocument: Decodable {
    let id: String
    let placeName: String
    let categoryName: String
    let addressName: String
    let roadAddressName: String
    let phone: String
    let distance: String
    let x: String
    let y: String
    let placeUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case placeName = "place_name"
        case categoryName = "category_name"
        case addressName = "address_name"
        case roadAddressName = "road_address_name"
        case phone
        case distance
        case x, y
        case placeUrl = "place_url"
    }

    func toPlaceResult() -> PlaceResult {
        // "음식점 > 이탈리안 > 파스타" → 마지막 세그먼트만 표시
        let shortCategory = categoryName
            .components(separatedBy: " > ")
            .last?.trimmingCharacters(in: .whitespaces) ?? categoryName
        return PlaceResult(
            id: id,
            name: placeName,
            category: shortCategory,
            address: roadAddressName.isEmpty ? addressName : roadAddressName,
            distanceMeters: Int(distance),
            phone: phone.isEmpty ? nil : phone,
            latitude: Double(y) ?? 0,
            longitude: Double(x) ?? 0,
            detailURL: placeUrl.isEmpty ? nil : placeUrl
        )
    }
}
