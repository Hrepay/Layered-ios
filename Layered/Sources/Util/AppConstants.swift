import Foundation

enum AppConstants {
    enum Family {
        /// 가정 최대 인원 (firestore.rules의 멤버 create 검증과 일치해야 함)
        static let maxMembers = 10
        /// 초대 코드 유효 시간(초)
        static let inviteCodeLifetime: TimeInterval = 1800
        static let inviteCodeLength = 6
    }

    enum Kakao {
        /// 카카오 로컬(장소 검색) REST API 키. 검색 전용 무료 키 — 노출 시에도 실질 리스크 낮음.
        /// 트래픽이 커지면 Cloud Functions 프록시로 이전 검토.
        static let restAPIKey = "KAKAO_REST_API_KEY_REMOVED"
    }

    enum Legal {
        static let termsVersion = "1.0"
        static let termsURL = URL(string: "https://hrepay.github.io/Layered/terms.html")!
        static let privacyURL = URL(string: "https://hrepay.github.io/Layered/privacy.html")!
        static let marketingURL = URL(string: "https://hrepay.github.io/Layered/marketing.html")!
    }
}
