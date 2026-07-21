import Foundation

protocol PlaceWishRepositoryProtocol {
    func getWishes(familyId: String) async throws -> [PlaceWish]
    func addWish(familyId: String, wish: PlaceWish) async throws
    func updateStatus(familyId: String, wishId: String, status: PlaceWish.Status) async throws
    func deleteWish(familyId: String, wishId: String) async throws
}
