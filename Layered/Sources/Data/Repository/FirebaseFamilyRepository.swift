import Foundation
import FirebaseFirestore
import FirebaseStorage

final class FirebaseFamilyRepository: FamilyRepositoryProtocol {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var familiesRef: CollectionReference { db.collection("families") }

    func createFamily(name: String, adminId: String) async throws -> Family {
        let inviteCode = try await generateUniqueCode()
        let expiresAt = Date().addingTimeInterval(AppConstants.Family.inviteCodeLifetime)
        let familyData: [String: Any] = [
            "name": name,
            "inviteCode": inviteCode,
            "inviteCodeExpiresAt": Timestamp(date: expiresAt),
            "adminId": adminId,
            "memberCount": 1,
            "currentPlannerIndex": 0,
            "rotationDay": 1,
            "rotationMode": "auto",
            "createdAt": Timestamp(date: Date()),
        ]

        let docRef = familiesRef.document()
        try await docRef.setData(familyData)

        // 생성자를 첫 번째 멤버로 추가
        let usersRef = db.collection("users")
        let userDoc = try await usersRef.document(adminId).getDocument()
        let userData = userDoc.data()
        let userName = userData?["name"] as? String ?? "사용자"
        let userImageURL = userData?["profileImageURL"] as? String

        try await docRef.collection("members").document(adminId).setData([
            "name": userName,
            "profileImageURL": userImageURL as Any,
            "role": "admin",
            "rotationOrder": 0,
            "joinedAt": Timestamp(date: Date()),
        ])

        // 코드 → 가정 매핑 (verifyInviteCode의 조회 경로. families 컬렉션 열거 없이 코드로만 접근)
        try await setInviteCodeMapping(code: inviteCode, familyId: docRef.documentID, expiresAt: expiresAt)

        // User의 familyId 업데이트
        try await usersRef.document(adminId).updateData(["familyId": docRef.documentID])

        return Family(
            id: docRef.documentID,
            name: name,
            inviteCode: inviteCode,
            inviteCodeExpiresAt: expiresAt,
            adminId: adminId,
            memberCount: 1,
            currentPlannerIndex: 0,
            rotationDay: 1,
            rotationMode: "auto",
            createdAt: Date()
        )
    }

    func getFamily(id: String) async throws -> Family {
        let doc = try await familiesRef.document(id).getDocument()
        guard let data = doc.data() else {
            throw NSError(domain: "family", code: -1, userInfo: [NSLocalizedDescriptionKey: "가정을 찾을 수 없습니다"])
        }
        return familyFromData(id: doc.documentID, data: data)
    }

    func deleteFamily(id: String) async throws {
        let familyRef = familiesRef.document(id)

        // 0. 초대 코드 매핑 정리 (멤버 문서 삭제 전 — 규칙상 멤버여야 삭제 가능)
        if let code = (try? await familyRef.getDocument())?.data()?["inviteCode"] as? String {
            let codeDoc = try? await inviteCodesRef.document(code).getDocument()
            if codeDoc?.data()?["familyId"] as? String == id {
                try? await inviteCodesRef.document(code).delete()
            }
        }

        // 1. meetings 전체 순회 — 각 모임의 polls·records·사진까지 cascade 삭제
        let meetingsSnapshot = try await familyRef.collection("meetings").getDocuments()
        for meetingDoc in meetingsSnapshot.documents {
            let meetingRef = meetingDoc.reference

            // polls 삭제
            let pollsSnapshot = try? await meetingRef.collection("polls").getDocuments()
            for pollDoc in pollsSnapshot?.documents ?? [] {
                try? await pollDoc.reference.delete()
            }

            // records 사진 + 문서 삭제
            let recordsSnapshot = try? await meetingRef.collection("records").getDocuments()
            for recordDoc in recordsSnapshot?.documents ?? [] {
                if let photos = recordDoc.data()["photos"] as? [String] {
                    for urlString in photos {
                        try? await deletePhotoByURL(urlString)
                    }
                }
                try? await recordDoc.reference.delete()
            }

            // 모임 문서 삭제
            try? await meetingRef.delete()
        }

        // 2. members 순회 — 각 유저의 familyId 초기화 + 멤버 문서 삭제
        let membersSnapshot = try await familyRef.collection("members").getDocuments()
        for memberDoc in membersSnapshot.documents {
            // 유저 문서의 familyId 제거 (규칙상 본인만 쓸 수 있으나, 탈퇴 시 관리자가 일괄 처리)
            try? await db.collection("users").document(memberDoc.documentID).updateData([
                "familyId": FieldValue.delete()
            ])
            try? await memberDoc.reference.delete()
        }

        // 3. family 문서 삭제
        try await familyRef.delete()
    }

    /// Firebase Storage 다운로드 URL로부터 참조를 구성해 삭제.
    private func deletePhotoByURL(_ urlString: String) async throws {
        guard urlString.contains("firebasestorage") else { return }
        let ref = storage.reference(forURL: urlString)
        try await ref.delete()
    }

    func updateFamilyName(familyId: String, name: String) async throws {
        try await familiesRef.document(familyId).updateData(["name": name])
    }

    func generateInviteCode(familyId: String) async throws -> String {
        // 이전 코드의 매핑 정리를 위해 현재 코드 조회
        let familyDoc = try await familiesRef.document(familyId).getDocument()
        let oldCode = familyDoc.data()?["inviteCode"] as? String

        let code = try await generateUniqueCode()
        let expiresAt = Date().addingTimeInterval(AppConstants.Family.inviteCodeLifetime)

        let batch = db.batch()
        if let oldCode, oldCode != code {
            // 매핑이 우리 가정 것일 때만 삭제 (과거 충돌 코드 방어)
            let oldDoc = try? await inviteCodesRef.document(oldCode).getDocument()
            if oldDoc?.data()?["familyId"] as? String == familyId {
                batch.deleteDocument(inviteCodesRef.document(oldCode))
            }
        }
        batch.setData([
            "familyId": familyId,
            "expiresAt": Timestamp(date: expiresAt),
            "createdAt": Timestamp(date: Date()),
        ], forDocument: inviteCodesRef.document(code))
        batch.updateData([
            "inviteCode": code,
            "inviteCodeExpiresAt": Timestamp(date: expiresAt),
        ], forDocument: familiesRef.document(familyId))
        try await batch.commit()
        return code
    }

    func verifyInviteCode(inviteCode: String) async throws -> Family {
        let invalidError = NSError(domain: "family", code: -1, userInfo: [NSLocalizedDescriptionKey: "유효하지 않은 코드입니다"])

        let codeDoc = try await inviteCodesRef.document(inviteCode).getDocument()
        guard let familyId = codeDoc.data()?["familyId"] as? String else {
            throw invalidError
        }

        let familyDoc = try await familiesRef.document(familyId).getDocument()
        guard let data = familyDoc.data(),
              data["inviteCode"] as? String == inviteCode else {
            throw invalidError
        }

        let expiresAt = (data["inviteCodeExpiresAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
        guard expiresAt > Date() else {
            throw NSError(domain: "family", code: -2, userInfo: [NSLocalizedDescriptionKey: "만료된 초대 코드입니다"])
        }

        let memberCount = data["memberCount"] as? Int ?? 0
        guard memberCount < AppConstants.Family.maxMembers else {
            throw NSError(domain: "family", code: -3, userInfo: [NSLocalizedDescriptionKey: "가정 최대 인원(\(AppConstants.Family.maxMembers)명)을 초과했습니다"])
        }

        return familyFromData(id: familyDoc.documentID, data: data)
    }

    func joinFamily(familyId: String, userId: String, userName: String, inviteCode: String) async throws {
        // users에서 프로필 이미지 가져오기 (트랜잭션 밖 — 검증 대상 아님)
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let userImageURL = userDoc.data()?["profileImageURL"] as? String

        let familyRef = familiesRef.document(familyId)
        let memberRef = familyRef.collection("members").document(userId)
        let userRef = db.collection("users").document(userId)
        let maxMembers = AppConstants.Family.maxMembers

        // 정원 확인 → rotationOrder 배정 → memberCount 증가를 원자화.
        // 동시 가입 시 rotationOrder 중복·정원 초과 방지.
        _ = try await db.runTransaction { transaction, errorPointer in
            let familySnap: DocumentSnapshot
            do {
                familySnap = try transaction.getDocument(familyRef)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            let data = familySnap.data() ?? [:]
            let memberCount = data["memberCount"] as? Int ?? 0

            let expiresAt = (data["inviteCodeExpiresAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
            guard data["inviteCode"] as? String == inviteCode, expiresAt > Date() else {
                errorPointer?.pointee = NSError(domain: "family", code: -2, userInfo: [NSLocalizedDescriptionKey: "만료된 초대 코드입니다"])
                return nil
            }
            guard memberCount < maxMembers else {
                errorPointer?.pointee = NSError(domain: "family", code: -3, userInfo: [NSLocalizedDescriptionKey: "가정 최대 인원(\(maxMembers)명)을 초과했습니다"])
                return nil
            }

            transaction.setData([
                "name": userName,
                "profileImageURL": userImageURL as Any,
                "role": "member",
                "rotationOrder": memberCount,
                // 보안 규칙이 초대 코드 제출을 검증하는 필드
                "joinCode": inviteCode,
                "joinedAt": Timestamp(date: Date()),
            ], forDocument: memberRef)
            transaction.updateData(["memberCount": memberCount + 1], forDocument: familyRef)
            transaction.updateData(["familyId": familyId], forDocument: userRef)
            return nil
        }
    }

    func updateRotationMode(familyId: String, mode: String) async throws {
        try await familiesRef.document(familyId).updateData(["rotationMode": mode])
    }

    func updateCurrentPlannerIndex(familyId: String, index: Int) async throws {
        try await familiesRef.document(familyId).updateData(["currentPlannerIndex": index])
    }

    // MARK: - Helpers
    private var inviteCodesRef: CollectionReference { db.collection("inviteCodes") }

    private func setInviteCodeMapping(code: String, familyId: String, expiresAt: Date) async throws {
        try await inviteCodesRef.document(code).setData([
            "familyId": familyId,
            "expiresAt": Timestamp(date: expiresAt),
            "createdAt": Timestamp(date: Date()),
        ])
    }

    /// 살아있는 다른 가정의 코드와 충돌하지 않는 코드를 생성.
    /// 만료된 매핑은 재사용 허용 — 코드 공간(36^6)이 넓어 재시도는 사실상 1회로 끝남.
    private func generateUniqueCode() async throws -> String {
        for _ in 0..<5 {
            let code = generateCode()
            let doc = try await inviteCodesRef.document(code).getDocument()
            if !doc.exists { return code }
            let expiresAt = (doc.data()?["expiresAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
            if expiresAt <= Date() { return code }
        }
        throw NSError(domain: "family", code: -4, userInfo: [NSLocalizedDescriptionKey: "초대 코드 생성에 실패했습니다. 잠시 후 다시 시도해주세요"])
    }

    private func generateCode() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<AppConstants.Family.inviteCodeLength).map { _ in chars.randomElement() ?? "0" })
    }

    private func familyFromData(id: String, data: [String: Any]) -> Family {
        Family(
            id: id,
            name: data["name"] as? String ?? "",
            inviteCode: data["inviteCode"] as? String ?? "",
            inviteCodeExpiresAt: (data["inviteCodeExpiresAt"] as? Timestamp)?.dateValue() ?? Date(),
            adminId: data["adminId"] as? String ?? "",
            memberCount: data["memberCount"] as? Int ?? 0,
            currentPlannerIndex: data["currentPlannerIndex"] as? Int ?? 0,
            rotationDay: data["rotationDay"] as? Int ?? 1,
            rotationMode: data["rotationMode"] as? String ?? "auto",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}
