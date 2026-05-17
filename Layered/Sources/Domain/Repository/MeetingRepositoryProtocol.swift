import Foundation

protocol MeetingRepositoryProtocol {
    func createMeeting(familyId: String, meeting: Meeting) async throws -> Meeting
    func getMeetings(familyId: String) async throws -> [Meeting]
    func getMeeting(familyId: String, meetingId: String) async throws -> Meeting
    func updateMeeting(familyId: String, meeting: Meeting) async throws
    func deleteMeeting(familyId: String, meetingId: String) async throws

    // MARK: - 참석 / 참여자 / 콕 찌르기
    /// 한 멤버의 참석 상태만 부분 업데이트. status가 nil이면 미정으로 되돌림.
    /// participantIds가 비어 있던 레거시 모임을 명시화하기 위해 명단도 함께 넘긴다.
    func setAttendance(familyId: String, meetingId: String, memberId: String, status: Meeting.AttendanceStatus?, participantIds: [String]) async throws
    /// 참여자 명단 교체. 명단에서 빠진 멤버의 참석 기록도 함께 제거.
    func setParticipants(familyId: String, meetingId: String, participantIds: [String]) async throws
    /// 콕 찌르기 — nudges 서브컬렉션에 문서를 남겨 Cloud Function 푸시를 트리거.
    func sendNudge(familyId: String, meetingId: String, fromUserId: String, fromName: String, targetUserId: String) async throws

    // MARK: - 모임 의견 (모든 모임에 달림 — 단일/후보 모드 무관)
    func getComments(familyId: String, meetingId: String) async throws -> [MeetingComment]
    func observeComments(familyId: String, meetingId: String) -> AsyncStream<[MeetingComment]>
    func addComment(familyId: String, meetingId: String, comment: MeetingComment) async throws -> MeetingComment
    func updateComment(familyId: String, meetingId: String, commentId: String, text: String) async throws
    func deleteComment(familyId: String, meetingId: String, commentId: String) async throws
}
