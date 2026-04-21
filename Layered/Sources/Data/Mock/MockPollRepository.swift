import Foundation

final class MockPollRepository: PollRepositoryProtocol {
    func createPoll(familyId: String, meetingId: String, poll: Poll) async throws -> Poll {
        poll
    }

    func getPolls(familyId: String, meetingId: String) async throws -> [Poll] {
        [MockData.poll]
    }

    func getPoll(familyId: String, meetingId: String, pollId: String) async throws -> Poll {
        MockData.poll
    }

    func vote(familyId: String, meetingId: String, pollId: String, optionId: String, userId: String) async throws {}

    func removeVote(familyId: String, meetingId: String, pollId: String, optionId: String, userId: String) async throws {}

    func addOption(familyId: String, meetingId: String, pollId: String, option: PollOption) async throws {}

    func updatePollOptions(familyId: String, meetingId: String, pollId: String, options: [PollOption]) async throws {}

    func deletePoll(familyId: String, meetingId: String, pollId: String) async throws {}
}
