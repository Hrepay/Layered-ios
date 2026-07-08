import Foundation
import FirebaseFirestore
import FirebaseStorage

final class FirebaseNoteRepository: NoteRepositoryProtocol {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private func notesRef(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId)
            .collection("notes")
    }

    func createNote(familyId: String, note: Note) async throws -> Note {
        var data: [String: Any] = [
            "authorId": note.authorId,
            "authorName": note.authorName,
            "text": note.text,
            "date": Timestamp(date: note.date),
            "createdAt": Timestamp(date: Date()),
            "updatedAt": Timestamp(date: Date()),
        ]
        if let photoURL = note.photoURL {
            data["photoURL"] = photoURL
        }

        // 사진 Storage 경로에 noteId가 필요하므로 문서 ID를 먼저 확보한 뒤 setData.
        let docRef = note.id.isEmpty ? notesRef(familyId: familyId).document() : notesRef(familyId: familyId).document(note.id)
        try await docRef.setData(data)

        return Note(
            id: docRef.documentID,
            authorId: note.authorId,
            authorName: note.authorName,
            text: note.text,
            photoURL: note.photoURL,
            date: note.date,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func getNotes(familyId: String) async throws -> [Note] {
        // 타임라인이 최신순이라 date desc로 미리 정렬해서 내려준다.
        let snapshot = try await notesRef(familyId: familyId)
            .order(by: "date", descending: true)
            .getDocuments()

        return snapshot.documents.map { noteFromDoc($0) }
    }

    func updateNote(familyId: String, note: Note) async throws {
        var data: [String: Any] = [
            "text": note.text,
            "date": Timestamp(date: note.date),
            "updatedAt": Timestamp(date: Date()),
        ]
        // 사진을 없앤 경우도 반영되도록 nil이면 필드 삭제.
        data["photoURL"] = note.photoURL ?? FieldValue.delete()
        try await notesRef(familyId: familyId).document(note.id).updateData(data)
    }

    func deleteNote(familyId: String, noteId: String) async throws {
        let noteRef = notesRef(familyId: familyId).document(noteId)

        // 사진 URL 확보 후 Storage에서 먼저 삭제. 실패해도 문서 삭제는 진행.
        if let data = try? await noteRef.getDocument().data(),
           let photoURL = data["photoURL"] as? String {
            try? await deletePhotoByURL(photoURL)
        }

        try await noteRef.delete()
    }

    private func deletePhotoByURL(_ urlString: String) async throws {
        guard urlString.contains("firebasestorage") else { return }
        let ref = storage.reference(forURL: urlString)
        try await ref.delete()
    }

    // MARK: - Helpers
    private func noteFromDoc(_ doc: QueryDocumentSnapshot) -> Note {
        let data = doc.data()
        return Note(
            id: doc.documentID,
            authorId: data["authorId"] as? String ?? "",
            authorName: data["authorName"] as? String ?? "",
            text: data["text"] as? String ?? "",
            photoURL: data["photoURL"] as? String,
            date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}
