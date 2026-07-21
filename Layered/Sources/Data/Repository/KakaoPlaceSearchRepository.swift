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
        radiusMeters: Int,
        latitude: Double?,
        longitude: Double?
    ) async throws -> [PlaceResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let radius = min(max(radiusMeters, 100), 20000)

        // "맛집만" + 좌표: 동네명 기반 인기 검색 (아래 popularSearch 주석 참고)
        if restaurantsOnly, let latitude, let longitude {
            return try await popularSearch(
                query: trimmed, category: category, radius: radius,
                latitude: latitude, longitude: longitude
            )
        }

        if trimmed.isEmpty {
            guard let latitude, let longitude else { return [] }
            // 좌표 기반 카테고리 탐색 (음식점/카페 그룹 전체, 거리순)
            return try await categorySearch(
                category: category, radius: radius, latitude: latitude, longitude: longitude
            )
        }
        return try await keywordSearch(
            query: trimmed, category: category, restaurantsOnly: restaurantsOnly,
            radius: radius, latitude: latitude, longitude: longitude
        )
    }

    // MARK: - 맛집만 + 내 주변: 동네명 기반 인기 검색

    /// 좌표를 동네명(법정동)으로 바꿔 "서초동 맛집"처럼 검색한다.
    /// 좌표+반경 검색은 근접도에 끌려가 바로 옆 가게 위주로 나오지만,
    /// 동네명 검색은 카카오의 언급량·인기 랭킹을 제대로 타서 유명한 곳이 상위로 온다 (실측 검증됨).
    /// 반경은 API가 아닌 클라이언트에서 거리 필터로 적용 — API radius는 상위 결과에 영향이 없었음.
    private func popularSearch(
        query: String,
        category: PlaceSearchCategory,
        radius: Int,
        latitude: Double,
        longitude: Double
    ) async throws -> [PlaceResult] {
        var parts: [String] = []
        if let region = try? await regionName(latitude: latitude, longitude: longitude) {
            parts.append(region)
        }
        switch category {
        case .all, .cafe: break
        default: parts.append(category.rawValue)
        }
        if !query.isEmpty {
            parts.append(query)
        }
        parts.append(category == .cafe ? "카페" : "맛집")
        let effectiveQuery = parts.joined(separator: " ")

        let groupCode = (category == .cafe) ? "CE7" : "FD6"
        // 3페이지(최대 45곳) 수집 후 반경·프랜차이즈 필터 — 인기순 유지
        var collected: [PlaceResult] = []
        for page in 1...3 {
            let items = [
                URLQueryItem(name: "query", value: effectiveQuery),
                URLQueryItem(name: "category_group_code", value: groupCode),
                URLQueryItem(name: "x", value: String(longitude)),
                URLQueryItem(name: "y", value: String(latitude)),
                URLQueryItem(name: "size", value: "15"),
                URLQueryItem(name: "page", value: String(page)),
            ]
            let response = try await requestPage(path: "keyword", queryItems: items)
            collected += response.documents.map { $0.toPlaceResult() }
            if response.meta.isEnd { break }
        }

        var seen = Set<String>()
        return collected
            .filter { seen.insert($0.id).inserted }
            .filter { ($0.distanceMeters ?? 0) <= radius }
            .filter { !Self.isFranchise($0.name) }
    }

    /// 좌표 → 법정동 이름 (예: "서초동"). 실패 시 nil — 호출부에서 좌표 검색으로 폴백.
    private func regionName(latitude: Double, longitude: Double) async throws -> String? {
        var components = URLComponents(string: "https://dapi.kakao.com/v2/local/geo/coord2regioncode.json")!
        components.queryItems = [
            URLQueryItem(name: "x", value: String(longitude)),
            URLQueryItem(name: "y", value: String(latitude)),
        ]
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("KakaoAK \(AppConstants.Kakao.restAPIKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: urlRequest)
        let decoded = try JSONDecoder().decode(KakaoRegionResponse.self, from: data)
        // B(법정동)가 "서초동"처럼 검색어로 자연스러움. 없으면 행정동.
        let region = decoded.documents.first { $0.regionType == "B" } ?? decoded.documents.first
        return region?.region3DepthName.isEmpty == false ? region?.region3DepthName : nil
    }

    /// "맛집만" 모드에서 걸러낼 대형 프랜차이즈. 이름 접두 일치 기준.
    private static let franchisePrefixes = [
        "맥도날드", "버거킹", "롯데리아", "KFC", "맘스터치", "서브웨이", "노브랜드버거",
        "스타벅스", "투썸플레이스", "이디야", "빽다방", "메가MGC", "메가커피", "컴포즈커피", "폴바셋",
        "파리바게뜨", "뚜레쥬르", "던킨", "배스킨라빈스",
        "김밥천국", "본죽", "한솥", "이삭토스트",
        "도미노피자", "피자헛", "미스터피자",
        "교촌치킨", "BBQ", "BHC", "굽네치킨", "네네치킨", "처갓집",
    ]

    private static func isFranchise(_ name: String) -> Bool {
        franchisePrefixes.contains { name.hasPrefix($0) }
    }

    // MARK: - 썸네일 폴백 (카카오 이미지 검색)

    /// 상세페이지 og:image가 없는 가게용 폴백 — 가게명으로 이미지 검색해 첫 썸네일 URL 반환.
    /// 공식 Daum 검색 API (같은 REST 키, 무료 쿼터 별도).
    static func fallbackThumbnailURL(placeName: String) async -> URL? {
        var components = URLComponents(string: "https://dapi.kakao.com/v2/search/image")!
        components.queryItems = [
            URLQueryItem(name: "query", value: placeName),
            URLQueryItem(name: "size", value: "1"),
        ]
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("KakaoAK \(AppConstants.Kakao.restAPIKey)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(KakaoImageSearchResponse.self, from: data),
              let thumbnail = decoded.documents.first?.thumbnailUrl else { return nil }
        return URL(string: thumbnail)
    }

    // MARK: - 요청 빌드

    private func keywordSearch(
        query: String,
        category: PlaceSearchCategory,
        restaurantsOnly: Bool,
        radius: Int,
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
            // 맛집만: 인기도(정확도) 정렬 — "가까운 순"이 아니라 "반경 내에서 유명한 순"
            items.append(contentsOf: [
                URLQueryItem(name: "x", value: String(longitude)),
                URLQueryItem(name: "y", value: String(latitude)),
                URLQueryItem(name: "radius", value: String(radius)),
                URLQueryItem(name: "sort", value: restaurantsOnly ? "accuracy" : "distance"),
            ])
        }
        return try await request(path: "keyword", queryItems: items)
    }

    private func categorySearch(
        category: PlaceSearchCategory,
        radius: Int,
        latitude: Double,
        longitude: Double
    ) async throws -> [PlaceResult] {
        let groupCode = (category == .cafe) ? "CE7" : "FD6"
        let items = [
            URLQueryItem(name: "category_group_code", value: groupCode),
            URLQueryItem(name: "x", value: String(longitude)),
            URLQueryItem(name: "y", value: String(latitude)),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "sort", value: "distance"),
            URLQueryItem(name: "size", value: "15"),
        ]
        let results = try await request(path: "category", queryItems: items)
        // 세부 업종 칩이면 카테고리명으로 클라이언트 필터 (카테고리 API는 그룹 단위까지만 지원)
        guard category != .all, category != .cafe else { return results }
        return results.filter { $0.category.contains(category.rawValue) }
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> [PlaceResult] {
        try await requestPage(path: path, queryItems: queryItems).documents.map { $0.toPlaceResult() }
    }

    private func requestPage(path: String, queryItems: [URLQueryItem]) async throws -> KakaoLocalResponse {
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
        return try JSONDecoder().decode(KakaoLocalResponse.self, from: data)
    }
}

// MARK: - 응답 디코딩

private struct KakaoLocalResponse: Decodable {
    let documents: [KakaoPlaceDocument]
    let meta: KakaoMeta
}

private struct KakaoMeta: Decodable {
    let isEnd: Bool

    enum CodingKeys: String, CodingKey {
        case isEnd = "is_end"
    }
}

private struct KakaoImageSearchResponse: Decodable {
    let documents: [KakaoImageDocument]
}

private struct KakaoImageDocument: Decodable {
    let thumbnailUrl: String

    enum CodingKeys: String, CodingKey {
        case thumbnailUrl = "thumbnail_url"
    }
}

private struct KakaoRegionResponse: Decodable {
    let documents: [KakaoRegionDocument]
}

private struct KakaoRegionDocument: Decodable {
    let regionType: String
    let region3DepthName: String

    enum CodingKeys: String, CodingKey {
        case regionType = "region_type"
        case region3DepthName = "region_3depth_name"
    }
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
        // API가 http URL을 주는데 ATS가 평문 요청을 막아 썸네일(og:image) 추출이 실패 → https로 승격
        let secureURL = placeUrl.replacingOccurrences(of: "http://", with: "https://")
        return PlaceResult(
            id: id,
            name: placeName,
            category: shortCategory,
            address: roadAddressName.isEmpty ? addressName : roadAddressName,
            distanceMeters: Int(distance),
            phone: phone.isEmpty ? nil : phone,
            latitude: Double(y) ?? 0,
            longitude: Double(x) ?? 0,
            detailURL: secureURL.isEmpty ? nil : secureURL
        )
    }
}
