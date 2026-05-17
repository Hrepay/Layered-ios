import Foundation

final class MockMeetingRepository: MeetingRepositoryProtocol {
    func createMeeting(familyId: String, meeting: Meeting) async throws -> Meeting {
        meeting
    }

    func getMeetings(familyId: String) async throws -> [Meeting] {
        MockData.meetings
    }

    func getMeeting(familyId: String, meetingId: String) async throws -> Meeting {
        MockData.meetings.first { $0.id == meetingId } ?? MockData.meetings[0]
    }

    func updateMeeting(familyId: String, meeting: Meeting) async throws {}

    func deleteMeeting(familyId: String, meetingId: String) async throws {}

    func setAttendance(familyId: String, meetingId: String, memberId: String, status: Meeting.AttendanceStatus?, participantIds: [String]) async throws {}

    func setParticipants(familyId: String, meetingId: String, participantIds: [String]) async throws {}

    func sendNudge(familyId: String, meetingId: String, fromUserId: String, fromName: String, targetUserId: String) async throws {}

    func getComments(familyId: String, meetingId: String) async throws -> [MeetingComment] { [] }

    func observeComments(familyId: String, meetingId: String) -> AsyncStream<[MeetingComment]> {
        AsyncStream { continuation in
            continuation.yield([])
            // 스트림을 finish하지 않고 열어둔다.
            // finish하면 뷰의 `for await` 루프가 즉시 종료되어 이후 Mock 상태 변경을
            // 반영할 수 없고, 실제 Firebase 스트림의 "뷰가 살아있는 동안 유지" 동작과
            // 다르게 동작해서 개발 중 혼란이 생김.
        }
    }

    func addComment(familyId: String, meetingId: String, comment: MeetingComment) async throws -> MeetingComment { comment }

    func updateComment(familyId: String, meetingId: String, commentId: String, text: String) async throws {}

    func deleteComment(familyId: String, meetingId: String, commentId: String) async throws {}
}
