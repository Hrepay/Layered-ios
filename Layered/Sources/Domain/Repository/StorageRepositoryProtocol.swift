import Foundation

protocol StorageRepositoryProtocol {
    func uploadProfileImage(userId: String, imageData: Data) async throws -> String
    func uploadRecordPhoto(familyId: String, meetingId: String, recordId: String, index: Int, imageData: Data) async throws -> String
    func uploadNotePhoto(familyId: String, noteId: String, imageData: Data) async throws -> String
    func deleteImage(path: String) async throws
    func deletePhotoByURL(_ urlString: String) async throws
}
