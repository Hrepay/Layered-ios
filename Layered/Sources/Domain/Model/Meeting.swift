import Foundation

struct Meeting: Identifiable, Codable, Hashable {
    let id: String
    var plannerId: String
    var plannerName: String
    var meetingDate: Date
    var place: String
    var placeLatitude: Double?
    var placeLongitude: Double?
    var placeURL: String?
    var activity: String?
    var status: Status
    var hasPoll: Bool
    let createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable {
        case planning
        case confirmed
        case completed
        case cancelled
    }
}

extension Meeting {
    /// UI 표시용 장소명. 투표 모드(후보 단계)면 placeholder로 대체.
    var displayPlace: String {
        if hasPoll && place.isEmpty { return "장소 투표 중" }
        return place
    }
}
