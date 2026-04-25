import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate, UIGestureRecognizerDelegate {
    /// 특정 화면(예: MeetingDiscussionView의 채팅형 UI)에서 전역 키보드 dismiss
    /// gesture를 일시적으로 끄기 위한 플래그. 해당 화면의 onAppear/onDisappear로 제어.
    static var suspendGlobalKeyboardDismiss: Bool = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        // 이미지 캐시 설정 (50MB 메모리, 200MB 디스크)
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )

        // 푸시 알림 설정
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // 알림 권한 요청
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }

        // 화면 어디든 탭하면 키보드 내림 (window 레벨 제스처)
        DispatchQueue.main.async { [weak self] in
            self?.installKeyboardDismissGesture()
        }

        return true
    }

    // MARK: - 글로벌 키보드 dismiss 제스처
    private func installKeyboardDismissGesture() {
        guard let window = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }

        let tap = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false   // 다른 탭/버튼 동작 보존
        tap.delegate = self                 // 다른 제스처와 동시 인식 허용
        window.addGestureRecognizer(tap)
    }

    // 다른 제스처(스크롤, 버튼 등)와 동시 인식 허용
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    // TextField/TextView 영역에서 시작된 터치는 받지 않음 (텍스트 선택/더블탭 보존).
    // 버튼성 UI(UIControl + accessibilityTraits에 .button 있는 SwiftUI Button) 영역도 제외 —
    // 버튼 탭 시 전역 endEditing이 키보드를 내렸다가 Button action이 다시 올리는 깜박임 방지.
    // SwiftUI Button은 iOS 17+ UIHostingController 안에서 UIControl로 래핑되지 않고
    // UIView에 accessibilityTraits만 부여하므로 trait 기반 체크가 필요.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // 채팅형 UI가 활성화된 화면에선 전역 dismiss 전체 비활성.
        if Self.suspendGlobalKeyboardDismiss { return false }

        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView || current is UIControl {
                return false
            }
            if current.accessibilityTraits.contains(.button) ||
               current.accessibilityTraits.contains(.link) {
                return false
            }
            view = current.superview
        }
        return true
    }

    // APNs 토큰 → FCM에 전달
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // FCM 토큰 갱신 시 Firestore에 저장
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        Task {
            await saveFCMToken(token)
        }
    }

    // 포그라운드에서 알림 수신 시 표시
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationCenter.default.post(name: .refreshFamilyData, object: nil)
        completionHandler([.banner, .badge, .sound])
    }

    // 알림 탭하고 앱으로 진입했을 때 홈 데이터 갱신 + deep-link 라우팅.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let link = DeepLink(userInfo: userInfo) {
            DeepLinkInbox.pending = link
            NotificationCenter.default.post(name: .deepLinkReceived, object: nil)
        }
        NotificationCenter.default.post(name: .refreshFamilyData, object: nil)
        completionHandler()
    }

    private func saveFCMToken(_ token: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        try? await db.collection("users").document(uid).updateData(["fcmToken": token])
    }
}

extension Notification.Name {
    static let refreshFamilyData = Notification.Name("refreshFamilyData")
}

@main
struct LayeredApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(AppColors.primary)
        }
    }
}
