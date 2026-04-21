import Foundation

protocol MeetingRepositoryProtocol {
    func createMeeting(familyId: String, meeting: Meeting) async throws -> Meeting
    func getMeetings(familyId: String) async throws -> [Meeting]
    func getMeeting(familyId: String, meetingId: String) async throws -> Meeting
    func updateMeeting(familyId: String, meeting: Meeting) async throws
    func deleteMeeting(familyId: String, meetingId: String) async throws

    // MARK: - 모임 의견 (모든 모임에 달림 — 단일/후보 모드 무관)
    func getComments(familyId: String, meetingId: String) async throws -> [MeetingComment]
    func addComment(familyId: String, meetingId: String, comment: MeetingComment) async throws -> MeetingComment
    func updateComment(familyId: String, meetingId: String, commentId: String, text: String) async throws
    func deleteComment(familyId: String, meetingId: String, commentId: String) async throws
}
