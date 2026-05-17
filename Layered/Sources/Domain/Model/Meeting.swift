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
    /// 모임 참여자(가족 멤버 id) 명단. 비어 있으면 "가족 전원"으로 간주 — 이 필드가
    /// 없던 시절에 만들어진 모임과의 호환을 위해 폴백 의미를 둔다.
    var participantIds: [String] = []
    /// 멤버 id → 참석 상태. 맵에 없는 멤버는 `미정`(참석 예정·미확정).
    var attendance: [String: AttendanceStatus] = [:]
    let createdAt: Date
    var updatedAt: Date

    enum Status: String, Codable {
        case planning
        case confirmed
        case completed
        case cancelled
    }

    enum AttendanceStatus: String, Codable {
        case going
        case notGoing
    }
}

extension Meeting {
    /// UI 표시용 장소명. 투표 모드(후보 단계)면 placeholder로 대체.
    var displayPlace: String {
        if hasPoll && place.isEmpty { return "장소 투표 중" }
        return place
    }

    /// 실제 참여자 id. 명단이 비어 있으면(레거시 모임) 가족 전원으로 폴백.
    func effectiveParticipantIds(allMemberIds: [String]) -> [String] {
        participantIds.isEmpty ? allMemberIds : participantIds
    }

    func attendanceStatus(for memberId: String) -> AttendanceStatus? {
        attendance[memberId]
    }
}
