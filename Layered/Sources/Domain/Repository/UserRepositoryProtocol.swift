import Foundation

struct NotificationSettings: Equatable {
    var enabled: Bool = true
    var plannerReminder: Bool = true
    var meetingCreated: Bool = true
    var meetingComment: Bool = true
    var meetingRecord: Bool = true
    var meetingDDay: Bool = true
}

protocol UserRepositoryProtocol {
    func getUser(id: String) async throws -> User
    func createUserIfNeeded(_ user: User) async throws
    func updateUser(_ user: User) async throws
    func loadNotificationSettings(userId: String) async throws -> NotificationSettings
    func updateNotificationSettings(userId: String, settings: NotificationSettings) async throws
    func recordTermsAgreement(userId: String, version: String, marketingConsent: Bool) async throws
}
