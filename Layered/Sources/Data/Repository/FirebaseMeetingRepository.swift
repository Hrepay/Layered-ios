import Foundation
import FirebaseFirestore
import FirebaseStorage

final class FirebaseMeetingRepository: MeetingRepositoryProtocol {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private func meetingsRef(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("meetings")
    }

    func createMeeting(familyId: String, meeting: Meeting) async throws -> Meeting {
        let data: [String: Any] = [
            "plannerId": meeting.plannerId,
            "plannerName": meeting.plannerName,
            "meetingDate": Timestamp(date: meeting.meetingDate),
            "place": meeting.place,
            "placeLatitude": meeting.placeLatitude as Any,
            "placeLongitude": meeting.placeLongitude as Any,
            "placeURL": meeting.placeURL as Any,
            "activity": meeting.activity as Any,
            "status": meeting.status.rawValue,
            "hasPoll": meeting.hasPoll,
            "participantIds": meeting.participantIds,
            "attendance": meeting.attendance.mapValues { $0.rawValue },
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
        ]

        let docRef = meetingsRef(familyId: familyId).document()
        try await docRef.setData(data)

        return Meeting(
            id: docRef.documentID,
            plannerId: meeting.plannerId,
            plannerName: meeting.plannerName,
            meetingDate: meeting.meetingDate,
            place: meeting.place,
            placeLatitude: meeting.placeLatitude,
            placeLongitude: meeting.placeLongitude,
            placeURL: meeting.placeURL,
            activity: meeting.activity,
            status: meeting.status,
            hasPoll: meeting.hasPoll,
            participantIds: meeting.participantIds,
            attendance: meeting.attendance,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func getMeetings(familyId: String) async throws -> [Meeting] {
        let snapshot = try await meetingsRef(familyId: familyId)
            .order(by: "meetingDate", descending: true)
            .getDocuments()

        return snapshot.documents.map { meetingFromDoc($0) }
    }

    func getMeeting(familyId: String, meetingId: String) async throws -> Meeting {
        let doc = try await meetingsRef(familyId: familyId).document(meetingId).getDocument()
        guard let data = doc.data() else {
            throw NSError(domain: "meeting", code: -1, userInfo: [NSLocalizedDescriptionKey: "모임을 찾을 수 없습니다"])
        }
        return meetingFromData(id: doc.documentID, data: data)
    }

    func updateMeeting(familyId: String, meeting: Meeting) async throws {
        var update: [String: Any] = [
            "meetingDate": Timestamp(date: meeting.meetingDate),
            "place": meeting.place,
            "placeLatitude": meeting.placeLatitude as Any,
            "placeLongitude": meeting.placeLongitude as Any,
            "placeURL": meeting.placeURL as Any,
            "activity": meeting.activity as Any,
            "status": meeting.status.rawValue,
            "hasPoll": meeting.hasPoll,
            "participantIds": meeting.participantIds,
            "updatedAt": Timestamp(date: Date()),
        ]
        // 최근 수정자 정보(AppState.updateMeeting에서 주입). 없으면 기존 값 유지(필드 미설정).
        if let editedAt = meeting.lastEditedAt {
            update["lastEditedAt"] = Timestamp(date: editedAt)
        }
        if let editorId = meeting.lastEditedById {
            update["lastEditedById"] = editorId
        }
        if let editorName = meeting.lastEditedByName {
            update["lastEditedByName"] = editorName
        }
        try await meetingsRef(familyId: familyId).document(meeting.id).updateData(update)
    }

    func deleteMeeting(familyId: String, meetingId: String) async throws {
        let meetingRef = meetingsRef(familyId: familyId).document(meetingId)

        // 1. polls 서브컬렉션 전부 삭제
        let pollsSnapshot = try await meetingRef.collection("polls").getDocuments()
        for pollDoc in pollsSnapshot.documents {
            try? await pollDoc.reference.delete()
        }

        // 2. comments 서브컬렉션 (모임 의견)
        let commentsSnapshot = try await meetingRef.collection("comments").getDocuments()
        for commentDoc in commentsSnapshot.documents {
            try? await commentDoc.reference.delete()
        }

        // 2-1. nudges 서브컬렉션 (콕 찌르기 트리거 기록)
        let nudgesSnapshot = try await meetingRef.collection("nudges").getDocuments()
        for nudgeDoc in nudgesSnapshot.documents {
            try? await nudgeDoc.reference.delete()
        }

        // 3. records 서브컬렉션 — 사진 URL까지 전부 Storage에서 삭제 후 문서 삭제
        let recordsSnapshot = try await meetingRef.collection("records").getDocuments()
        for recordDoc in recordsSnapshot.documents {
            if let photos = recordDoc.data()["photos"] as? [String] {
                for urlString in photos {
                    try? await deletePhotoByURL(urlString)
                }
            }
            try? await recordDoc.reference.delete()
        }

        // 4. meeting 문서 자체 삭제
        try await meetingRef.delete()
    }

    // MARK: - 참석 / 참여자 / 콕 찌르기

    func setAttendance(familyId: String, meetingId: String, memberId: String, status: Meeting.AttendanceStatus?, participantIds: [String]) async throws {
        var update: [String: Any] = [
            "updatedAt": Timestamp(date: Date()),
        ]
        // 점경로 부분 업데이트라 다른 멤버 상태/모임 필드와 충돌하지 않음.
        update["attendance.\(memberId)"] = status?.rawValue ?? FieldValue.delete()
        // 명단이 비어 있던 레거시 모임이면 이번 기회에 전원으로 명시화.
        if !participantIds.isEmpty {
            update["participantIds"] = participantIds
        }
        try await meetingsRef(familyId: familyId).document(meetingId).updateData(update)
    }

    func setParticipants(familyId: String, meetingId: String, participantIds: [String]) async throws {
        let docRef = meetingsRef(familyId: familyId).document(meetingId)
        let snapshot = try await docRef.getDocument()
        let attendance = snapshot.data()?["attendance"] as? [String: String] ?? [:]
        // 명단에서 빠진 멤버의 참석 기록은 정리.
        let removed = Set(attendance.keys).subtracting(participantIds)
        var update: [String: Any] = [
            "participantIds": participantIds,
            "updatedAt": Timestamp(date: Date()),
        ]
        for memberId in removed {
            update["attendance.\(memberId)"] = FieldValue.delete()
        }
        try await docRef.updateData(update)
    }

    func sendNudge(familyId: String, meetingId: String, fromUserId: String, fromName: String, targetUserId: String) async throws {
        let docRef = meetingsRef(familyId: familyId)
            .document(meetingId)
            .collection("nudges")
            .document()
        try await docRef.setData([
            "fromUserId": fromUserId,
            "fromName": fromName,
            "targetUserId": targetUserId,
            "createdAt": Timestamp(date: Date()),
        ])
    }

    // MARK: - 모임 의견

    private func commentsRef(familyId: String, meetingId: String) -> CollectionReference {
        meetingsRef(familyId: familyId).document(meetingId).collection("comments")
    }

    func getComments(familyId: String, meetingId: String) async throws -> [MeetingComment] {
        let snapshot = try await commentsRef(familyId: familyId, meetingId: meetingId)
            .order(by: "createdAt", descending: false)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let userId = data["userId"] as? String,
                  let userName = data["userName"] as? String,
                  let text = data["text"] as? String,
                  let ts = data["createdAt"] as? Timestamp else { return nil }
            return MeetingComment(
                id: doc.documentID,
                userId: userId,
                userName: userName,
                text: text,
                createdAt: ts.dateValue()
            )
        }
    }

    func observeComments(familyId: String, meetingId: String) -> AsyncStream<[MeetingComment]> {
        AsyncStream { continuation in
            let listener = commentsRef(familyId: familyId, meetingId: meetingId)
                .order(by: "createdAt", descending: false)
                .addSnapshotListener { snapshot, _ in
                    guard let snapshot else { return }
                    let comments = snapshot.documents.compactMap { doc -> MeetingComment? in
                        let data = doc.data()
                        guard let userId = data["userId"] as? String,
                              let userName = data["userName"] as? String,
                              let text = data["text"] as? String,
                              let ts = data["createdAt"] as? Timestamp else { return nil }
                        return MeetingComment(
                            id: doc.documentID,
                            userId: userId,
                            userName: userName,
                            text: text,
                            createdAt: ts.dateValue()
                        )
                    }
                    continuation.yield(comments)
                }
            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func addComment(familyId: String, meetingId: String, comment: MeetingComment) async throws -> MeetingComment {
        let docRef = commentsRef(familyId: familyId, meetingId: meetingId).document()
        let now = Date()
        let data: [String: Any] = [
            "userId": comment.userId,
            "userName": comment.userName,
            "text": comment.text,
            "createdAt": Timestamp(date: now),
        ]
        try await docRef.setData(data)
        return MeetingComment(
            id: docRef.documentID,
            userId: comment.userId,
            userName: comment.userName,
            text: comment.text,
            createdAt: now
        )
    }

    func updateComment(familyId: String, meetingId: String, commentId: String, text: String) async throws {
        try await commentsRef(familyId: familyId, meetingId: meetingId)
            .document(commentId)
            .updateData([
                "text": text,
                "updatedAt": Timestamp(date: Date()),
            ])
    }

    func deleteComment(familyId: String, meetingId: String, commentId: String) async throws {
        try await commentsRef(familyId: familyId, meetingId: meetingId)
            .document(commentId).delete()
    }

    /// Firebase Storage 다운로드 URL로부터 참조를 구성해 삭제.
    /// Mock asset:// 이나 picsum 같은 외부 URL은 무시.
    private func deletePhotoByURL(_ urlString: String) async throws {
        guard urlString.contains("firebasestorage") else { return }
        let ref = storage.reference(forURL: urlString)
        try await ref.delete()
    }

    // MARK: - Helpers
    private func meetingFromDoc(_ doc: QueryDocumentSnapshot) -> Meeting {
        meetingFromData(id: doc.documentID, data: doc.data())
    }

    private func meetingFromData(id: String, data: [String: Any]) -> Meeting {
        Meeting(
            id: id,
            plannerId: data["plannerId"] as? String ?? "",
            plannerName: data["plannerName"] as? String ?? "",
            meetingDate: (data["meetingDate"] as? Timestamp)?.dateValue() ?? Date(),
            place: data["place"] as? String ?? "",
            placeLatitude: data["placeLatitude"] as? Double,
            placeLongitude: data["placeLongitude"] as? Double,
            placeURL: data["placeURL"] as? String,
            activity: data["activity"] as? String,
            status: Meeting.Status(rawValue: data["status"] as? String ?? "planning") ?? .planning,
            hasPoll: data["hasPoll"] as? Bool ?? false,
            participantIds: data["participantIds"] as? [String] ?? [],
            attendance: (data["attendance"] as? [String: String] ?? [:])
                .compactMapValues { Meeting.AttendanceStatus(rawValue: $0) },
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
            lastEditedAt: (data["lastEditedAt"] as? Timestamp)?.dateValue(),
            lastEditedById: data["lastEditedById"] as? String,
            lastEditedByName: data["lastEditedByName"] as? String
        )
    }
}
