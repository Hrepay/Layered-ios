import Foundation
import UIKit
import FirebaseStorage

final class FirebaseStorageRepository: StorageRepositoryProtocol {
    private let storage = Storage.storage()

    func uploadProfileImage(userId: String, imageData: Data) async throws -> String {
        let path = "users/\(userId)/profile.jpg"
        return try await uploadData(imageData, path: path)
    }

    func uploadRecordPhoto(familyId: String, meetingId: String, recordId: String, index: Int, imageData: Data) async throws -> String {
        let path = "families/\(familyId)/meetings/\(meetingId)/records/\(recordId)/photo_\(index).jpg"
        return try await uploadData(imageData, path: path)
    }

    func uploadNotePhoto(familyId: String, noteId: String, imageData: Data) async throws -> String {
        let path = "families/\(familyId)/notes/\(noteId)/photo.jpg"
        return try await uploadData(imageData, path: path)
    }

    func deleteImage(path: String) async throws {
        let ref = storage.reference().child(path)
        try await ref.delete()
    }

    /// Firebase Storage 다운로드 URL로부터 참조를 구성해 삭제. firebasestorage URL만 대상.
    func deletePhotoByURL(_ urlString: String) async throws {
        guard urlString.contains("firebasestorage") else { return }
        let ref = storage.reference(forURL: urlString)
        try await ref.delete()
    }

    // MARK: - Private

    private func uploadData(_ data: Data, path: String) async throws -> String {
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

}
