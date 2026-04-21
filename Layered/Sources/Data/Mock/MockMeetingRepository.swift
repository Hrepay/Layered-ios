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

    func getComments(familyId: String, meetingId: String) async throws -> [MeetingComment] { [] }

    func addComment(familyId: String, meetingId: String, comment: MeetingComment) async throws -> MeetingComment { comment }

    func updateComment(familyId: String, meetingId: String, commentId: String, text: String) async throws {}

    func deleteComment(familyId: String, meetingId: String, commentId: String) async throws {}
}
