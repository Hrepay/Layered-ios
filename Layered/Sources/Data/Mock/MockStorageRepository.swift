import Foundation

final class MockStorageRepository: StorageRepositoryProtocol {
    func uploadProfileImage(userId: String, imageData: Data) async throws -> String {
        "https://picsum.photos/seed/avatar\(userId)/400/400"
    }

    func uploadRecordPhoto(familyId: String, meetingId: String, recordId: String, index: Int, imageData: Data) async throws -> String {
        "https://picsum.photos/seed/record\(recordId)\(index)/800/800"
    }

    func deleteImage(path: String) async throws {}

    func deletePhotoByURL(_ urlString: String) async throws {}
}
