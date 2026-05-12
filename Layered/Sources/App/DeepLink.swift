import Foundation

enum DeepLink: Equatable {
    case meetingComment(meetingId: String)
    case meetingRecord(meetingId: String)
}

extension DeepLink {
    /// FCM userInfo 포맷: { "type": "meetingComment" | "meetingRecord", "meetingId": "..." }
    init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return nil }
        guard let meetingId = userInfo["meetingId"] as? String,
              !meetingId.isEmpty else { return nil }
        switch type {
        case "meetingComment":
            self = .meetingComment(meetingId: meetingId)
        case "meetingRecord":
            self = .meetingRecord(meetingId: meetingId)
        default:
            return nil
        }
    }
}

/// AppDelegate가 알림 탭 시점에 deep-link을 던져두는 정적 인박스.
/// AppState/뷰 트리가 아직 살아있지 않은 콜드 스타트 케이스를 안전하게 받기 위해 분리.
enum DeepLinkInbox {
    nonisolated(unsafe) static var pending: DeepLink?
}

extension Notification.Name {
    static let deepLinkReceived = Notification.Name("deepLinkReceived")
}
