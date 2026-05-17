import Foundation
import FirebaseFirestore

final class FirebaseUserRepository: UserRepositoryProtocol {
    private let db = Firestore.firestore()
    private var usersRef: CollectionReference { db.collection("users") }

    func getUser(id: String) async throws -> User {
        let doc = try await usersRef.document(id).getDocument()
        guard let data = doc.data() else {
            throw NSError(domain: "user", code: -1, userInfo: [NSLocalizedDescriptionKey: "사용자를 찾을 수 없습니다"])
        }
        return userFromData(id: doc.documentID, data: data)
    }

    func createUserIfNeeded(_ user: User) async throws {
        let docRef = usersRef.document(user.id)
        let doc = try await docRef.getDocument()

        if !doc.exists {
            try await docRef.setData([
                "name": user.name,
                "profileImageURL": user.profileImageURL as Any,
                "familyId": user.familyId as Any,
                "createdAt": Timestamp(date: user.createdAt),
            ])
        }
    }

    func updateUser(_ user: User) async throws {
        try await usersRef.document(user.id).updateData([
            "name": user.name,
            "profileImageURL": user.profileImageURL as Any,
            "familyId": user.familyId as Any,
        ])
    }

    func loadNotificationSettings(userId: String) async throws -> NotificationSettings {
        let doc = try await usersRef.document(userId).getDocument()
        let data = doc.data() ?? [:]
        return NotificationSettings(
            enabled: data["notificationsEnabled"] as? Bool ?? true,
            plannerReminder: data["notifyPlannerReminder"] as? Bool ?? true,
            meetingCreated: data["notifyMeetingCreated"] as? Bool ?? true,
            meetingComment: data["notifyMeetingComment"] as? Bool ?? true,
            meetingRecord: data["notifyMeetingRecord"] as? Bool ?? true,
            meetingDDay: data["notifyMeetingDDay"] as? Bool ?? true,
            nudge: data["notifyNudge"] as? Bool ?? true
        )
    }

    func updateNotificationSettings(userId: String, settings: NotificationSettings) async throws {
        try await usersRef.document(userId).updateData([
            "notificationsEnabled": settings.enabled,
            "notifyPlannerReminder": settings.plannerReminder,
            "notifyMeetingCreated": settings.meetingCreated,
            "notifyMeetingComment": settings.meetingComment,
            "notifyMeetingRecord": settings.meetingRecord,
            "notifyMeetingDDay": settings.meetingDDay,
            "notifyNudge": settings.nudge,
        ])
    }

    func recordTermsAgreement(userId: String, version: String, marketingConsent: Bool) async throws {
        try await usersRef.document(userId).setData([
            "agreedTermsAt": Timestamp(date: Date()),
            "agreedTermsVersion": version,
            "marketingConsent": marketingConsent,
        ], merge: true)
    }

    // MARK: - Helper
    private func userFromData(id: String, data: [String: Any]) -> User {
        User(
            id: id,
            name: data["name"] as? String ?? "사용자",
            profileImageURL: data["profileImageURL"] as? String,
            familyId: data["familyId"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            agreedTermsAt: (data["agreedTermsAt"] as? Timestamp)?.dateValue(),
            agreedTermsVersion: data["agreedTermsVersion"] as? String,
            marketingConsent: data["marketingConsent"] as? Bool
        )
    }
}
