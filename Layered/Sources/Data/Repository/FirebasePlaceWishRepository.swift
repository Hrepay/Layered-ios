import Foundation
import FirebaseFirestore

final class FirebasePlaceWishRepository: PlaceWishRepositoryProtocol {
    private let db = Firestore.firestore()

    private func wishesRef(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("placeWishes")
    }

    func getWishes(familyId: String) async throws -> [PlaceWish] {
        let snapshot = try await wishesRef(familyId: familyId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snapshot.documents.map { wishFromData(id: $0.documentID, data: $0.data()) }
    }

    func addWish(familyId: String, wish: PlaceWish) async throws {
        try await wishesRef(familyId: familyId).document(wish.id).setData([
            "placeId": wish.placeId,
            "name": wish.name,
            "category": wish.category,
            "address": wish.address,
            "latitude": wish.latitude,
            "longitude": wish.longitude,
            "detailURL": wish.detailURL as Any,
            "phone": wish.phone as Any,
            "recommenderId": wish.recommenderId,
            "recommenderName": wish.recommenderName,
            "status": wish.status.rawValue,
            "createdAt": Timestamp(date: wish.createdAt),
        ])
    }

    func updateStatus(familyId: String, wishId: String, status: PlaceWish.Status) async throws {
        var update: [String: Any] = ["status": status.rawValue]
        if status == .visited {
            update["visitedAt"] = Timestamp(date: Date())
        } else {
            update["visitedAt"] = FieldValue.delete()
        }
        try await wishesRef(familyId: familyId).document(wishId).updateData(update)
    }

    func deleteWish(familyId: String, wishId: String) async throws {
        try await wishesRef(familyId: familyId).document(wishId).delete()
    }

    // MARK: - Helpers
    private func wishFromData(id: String, data: [String: Any]) -> PlaceWish {
        PlaceWish(
            id: id,
            placeId: data["placeId"] as? String ?? "",
            name: data["name"] as? String ?? "",
            category: data["category"] as? String ?? "",
            address: data["address"] as? String ?? "",
            latitude: data["latitude"] as? Double ?? 0,
            longitude: data["longitude"] as? Double ?? 0,
            detailURL: data["detailURL"] as? String,
            phone: data["phone"] as? String,
            recommenderId: data["recommenderId"] as? String ?? "",
            recommenderName: data["recommenderName"] as? String ?? "",
            status: PlaceWish.Status(rawValue: data["status"] as? String ?? "wishlist") ?? .wishlist,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            visitedAt: (data["visitedAt"] as? Timestamp)?.dateValue()
        )
    }
}
