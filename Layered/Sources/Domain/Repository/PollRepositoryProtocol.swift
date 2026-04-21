import Foundation

protocol PollRepositoryProtocol {
    func createPoll(familyId: String, meetingId: String, poll: Poll) async throws -> Poll
    func getPolls(familyId: String, meetingId: String) async throws -> [Poll]
    func getPoll(familyId: String, meetingId: String, pollId: String) async throws -> Poll
    func vote(familyId: String, meetingId: String, pollId: String, optionId: String, userId: String) async throws
    func removeVote(familyId: String, meetingId: String, pollId: String, optionId: String, userId: String) async throws
    func addOption(familyId: String, meetingId: String, pollId: String, option: PollOption) async throws
    /// 기존 옵션 ID와 매칭되는 항목은 voterIds/voteCount를 보존, 새 ID는 빈 voterIds로 추가, 매칭 안 되는 기존 옵션은 제거.
    func updatePollOptions(familyId: String, meetingId: String, pollId: String, options: [PollOption]) async throws
    func deletePoll(familyId: String, meetingId: String, pollId: String) async throws
}
