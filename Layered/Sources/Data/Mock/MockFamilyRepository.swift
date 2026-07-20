import Foundation

final class MockFamilyRepository: FamilyRepositoryProtocol {
    func createFamily(name: String, adminId: String) async throws -> Family {
        MockData.family
    }

    func getFamily(id: String) async throws -> Family {
        MockData.family
    }

    func deleteFamily(id: String) async throws {}
    func updateFamilyName(familyId: String, name: String) async throws {}

    func generateInviteCode(familyId: String) async throws -> String {
        "ABC123"
    }

    func verifyInviteCode(inviteCode: String) async throws -> Family {
        MockData.family
    }
    func joinFamily(familyId: String, userId: String, userName: String, inviteCode: String) async throws {}
    func updateRotationMode(familyId: String, mode: String) async throws {}
    func updateCurrentPlannerIndex(familyId: String, index: Int) async throws {}
}
