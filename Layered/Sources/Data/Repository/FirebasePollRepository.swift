import Foundation
import FirebaseFirestore

final class FirebasePollRepository: PollRepositoryProtocol {
    private let db = Firestore.firestore()

    private func pollsRef(familyId: String, meetingId: String) -> CollectionReference {
        db.collection("families").document(familyId)
            .collection("meetings").document(meetingId)
            .collection("polls")
    }

    func createPoll(familyId: String, meetingId: String, poll: Poll) async throws -> Poll {
        let optionsData: [[String: Any]] = poll.options.map { option in
            [
                "id": option.id,
                "title": option.title,
                "description": option.description as Any,
                "imageURL": option.imageURL as Any,
                "linkURL": option.linkURL as Any,
                "voterIds": option.voterIds,
                "voteCount": option.voteCount,
            ]
        }

        let data: [String: Any] = [
            "question": poll.question,
            "isAnonymous": poll.isAnonymous,
            "allowMultiple": poll.allowMultiple,
            "options": optionsData,
            "createdAt": Timestamp(date: Date()),
        ]

        let docRef = pollsRef(familyId: familyId, meetingId: meetingId).document()
        try await docRef.setData(data)

        // meeting.hasPoll = true
        try await db.collection("families").document(familyId)
            .collection("meetings").document(meetingId)
            .updateData(["hasPoll": true])

        return Poll(
            id: docRef.documentID,
            question: poll.question,
            isAnonymous: poll.isAnonymous,
            allowMultiple: poll.allowMultiple,
            options: poll.options,
            createdAt: Date()
        )
    }

    func getPolls(familyId: String, meetingId: String) async throws -> [Poll] {
        let snapshot = try await pollsRef(familyId: familyId, meetingId: meetingId).getDocuments()
        return snapshot.documents.map { doc in
            pollFromData(id: doc.documentID, data: doc.data())
        }
    }

    func getPoll(familyId: String, meetingId: String, pollId: String) async throws -> Poll {
        let doc = try await pollsRef(familyId: familyId, meetingId: meetingId).document(pollId).getDocument()
        guard let data = doc.data() else {
            throw NSError(domain: "poll", code: -1, userInfo: [NSLocalizedDescriptionKey: "투표를 찾을 수 없습니다"])
        }
        return pollFromData(id: doc.documentID, data: data)
    }

    func vote(familyId: String, meetingId: String, pollId: String, optionId: String, userId: String) async throws {
        let ref = pollsRef(familyId: familyId, meetingId: meetingId).document(pollId)
        // 트랜잭션으로 read-modify-write 원자화. 동시 투표 시 표 유실 방지.
        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard let data = snapshot.data(),
                  var options = data["options"] as? [[String: Any]] else { return nil }
            let isAnonymous = data["isAnonymous"] as? Bool ?? false

            for i in options.indices {
                guard let id = options[i]["id"] as? String, id == optionId else { continue }
                if isAnonymous {
                    options[i]["voteCount"] = (options[i]["voteCount"] as? Int ?? 0) + 1
                } else {
                    var voterIds = options[i]["voterIds"] as? [String] ?? []
                    if !voterIds.contains(userId) {
                        voterIds.append(userId)
                        options[i]["voterIds"] = voterIds
                        options[i]["voteCount"] = voterIds.count
                    }
                }
            }
            transaction.updateData(["options": options], forDocument: ref)
            return nil
        }
    }

    func removeVote(familyId: String, meetingId: String, pollId: String, optionId: String, userId: String) async throws {
        let ref = pollsRef(familyId: familyId, meetingId: meetingId).document(pollId)
        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard let data = snapshot.data(),
                  var options = data["options"] as? [[String: Any]] else { return nil }

            for i in options.indices {
                guard let id = options[i]["id"] as? String, id == optionId else { continue }
                var voterIds = options[i]["voterIds"] as? [String] ?? []
                voterIds.removeAll { $0 == userId }
                options[i]["voterIds"] = voterIds
                options[i]["voteCount"] = max(0, (options[i]["voteCount"] as? Int ?? 1) - 1)
            }
            transaction.updateData(["options": options], forDocument: ref)
            return nil
        }
    }

    func addOption(familyId: String, meetingId: String, pollId: String, option: PollOption) async throws {
        let ref = pollsRef(familyId: familyId, meetingId: meetingId).document(pollId)
        // 동시 추가 시 옵션 유실 방지
        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            guard let data = snapshot.data() else { return nil }
            var options = data["options"] as? [[String: Any]] ?? []
            options.append([
                "id": option.id,
                "title": option.title,
                "description": option.description as Any,
                "imageURL": option.imageURL as Any,
                "linkURL": option.linkURL as Any,
                "voterIds": [String](),
                "voteCount": 0,
            ])
            transaction.updateData(["options": options], forDocument: ref)
            return nil
        }
    }

    func updatePollOptions(familyId: String, meetingId: String, pollId: String, options: [PollOption]) async throws {
        let ref = pollsRef(familyId: familyId, meetingId: meetingId).document(pollId)
        // 트랜잭션으로 기존 voterIds 보존하며 옵션 배열 교체.
        _ = try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            let existing = (snapshot.data()? ["options"] as? [[String: Any]]) ?? []
            var voterMap: [String: ([String], Int)] = [:]
            for opt in existing {
                guard let id = opt["id"] as? String else { continue }
                voterMap[id] = (opt["voterIds"] as? [String] ?? [], opt["voteCount"] as? Int ?? 0)
            }
            let merged: [[String: Any]] = options.map { option in
                let preserved = voterMap[option.id] ?? ([], 0)
                return [
                    "id": option.id,
                    "title": option.title,
                    "description": option.description as Any,
                    "imageURL": option.imageURL as Any,
                    "linkURL": option.linkURL as Any,
                    "voterIds": preserved.0,
                    "voteCount": preserved.1,
                ]
            }
            transaction.updateData(["options": merged], forDocument: ref)
            return nil
        }
    }

    func deletePoll(familyId: String, meetingId: String, pollId: String) async throws {
        // hasPoll 업데이트를 먼저 수행해 UI(투표 뱃지)가 곧바로 옳게 반영되게 함.
        // 투표 문서는 그 다음 삭제. 두 단계 중 한 쪽만 실패해도 UI는 정합성 유지.
        try await db.collection("families").document(familyId)
            .collection("meetings").document(meetingId)
            .updateData(["hasPoll": false])
        try await pollsRef(familyId: familyId, meetingId: meetingId).document(pollId).delete()
    }

    // MARK: - Helpers
    private func pollFromData(id: String, data: [String: Any]) -> Poll {
        let optionsData = data["options"] as? [[String: Any]] ?? []
        let options = optionsData.map { opt in
            PollOption(
                id: opt["id"] as? String ?? UUID().uuidString,
                title: opt["title"] as? String ?? "",
                description: opt["description"] as? String,
                imageURL: opt["imageURL"] as? String,
                linkURL: opt["linkURL"] as? String,
                voterIds: opt["voterIds"] as? [String] ?? [],
                voteCount: opt["voteCount"] as? Int ?? 0
            )
        }

        return Poll(
            id: id,
            question: data["question"] as? String ?? "",
            isAnonymous: data["isAnonymous"] as? Bool ?? false,
            allowMultiple: data["allowMultiple"] as? Bool ?? false,
            options: options,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}
