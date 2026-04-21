import Foundation

struct MeetingComment: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    var userName: String
    var text: String
    let createdAt: Date
}
