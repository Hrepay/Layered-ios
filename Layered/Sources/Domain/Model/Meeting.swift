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
    /// 가장 최근 EditMeetingView·후보 확정 등 "수정"으로 간주되는 액션이 일어난 시각.
    /// 출석 변경·콕 찌르기 같은 운영성 변경은 updatedAt만 갱신하고 이 필드는 건드리지 않는다.
    var lastEditedAt: Date? = nil
    var lastEditedById: String? = nil
    /// 표시용 비정규화 이름. 변경 시점의 사용자명을 박제 — 이후 가족에서 나가도 표시 유지.
    var lastEditedByName: String? = nil

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
