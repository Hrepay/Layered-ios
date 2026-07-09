import Foundation

/// 모임으로 정하기엔 애매하거나 그냥저냥 지나간 주에, 그래도 흔적을 남기고 싶을 때 쓰는 "한 겹".
/// 모임(Meeting)에 종속되지 않는 독립 메모 — 별점·다중사진 없이 한 줄 + 선택 사진 1장으로 가볍게.
/// Firestore: `families/{familyId}/notes/{noteId}`
struct Note: Identifiable, Codable {
    let id: String
    var authorId: String
    var authorName: String
    var text: String
    /// 선택 사진 1장. 없으면 nil.
    var photoURL: String?
    /// 이 한 겹에 함께한 가족 id. 비어 있으면 작성자만.
    var participantIds: [String]
    /// 이 메모가 가리키는 날 (기본 오늘). 히스토리 타임라인·연속 주 계산의 기준.
    var date: Date
    let createdAt: Date
    var updatedAt: Date
}
