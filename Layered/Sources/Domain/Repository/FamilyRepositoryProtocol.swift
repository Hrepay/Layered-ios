import Foundation

protocol FamilyRepositoryProtocol {
    func createFamily(name: String, adminId: String) async throws -> Family
    func getFamily(id: String) async throws -> Family
    func deleteFamily(id: String) async throws
    func updateFamilyName(familyId: String, name: String) async throws
    func generateInviteCode(familyId: String) async throws -> String
    func verifyInviteCode(inviteCode: String) async throws -> Family
    func joinFamily(familyId: String, userId: String, userName: String, inviteCode: String) async throws
    func updateRotationMode(familyId: String, mode: String) async throws
    func updateCurrentPlannerIndex(familyId: String, index: Int) async throws
}
