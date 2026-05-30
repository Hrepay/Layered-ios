import SwiftUI

/// 한 옵션에 투표한 사람들의 아바타 스택 + 이름/+N 라벨.
/// MeetingDetailView 후보 행과 MeetingDiscussionView 옵션 행에서 공유.
///
/// 표시 조건:
/// - poll.isAnonymous == false (호출자가 검사)
/// - voterIds가 비어있지 않을 때(호출자가 검사) 사용
///
/// 가족에서 이미 나간 멤버는 회색 `?` 아바타로 표기해 이력 보존.
struct PollVoterAvatars: View {
    let voterIds: [String]
    let members: [Member]
    var avatarSize: CGFloat = 22

    private var resolved: [(id: String, name: String, imageURL: String?)] {
        voterIds.map { id in
            if let m = members.first(where: { $0.id == id }) {
                return (id, m.name, m.profileImageURL)
            } else {
                return (id, "?", nil)
            }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: -6) {
                ForEach(Array(resolved.prefix(5).enumerated()), id: \.offset) { _, voter in
                    AvatarView(name: voter.name, size: avatarSize, imageURL: voter.imageURL)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                }
            }
            if resolved.count > 5 {
                Text("+\(resolved.count - 5)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            } else {
                Text(resolved.map(\.name).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
