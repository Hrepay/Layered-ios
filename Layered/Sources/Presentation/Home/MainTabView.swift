import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Int = 0

    var body: some View {
        Group {
            if let family = appState.currentFamily,
               let user = appState.currentUser {
                TabView(selection: $selectedTab) {
                    HomeView(
                        family: family,
                        members: appState.members,
                        meetings: appState.meetings,
                        currentUser: user
                    )
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("홈")
                    }
                    .tag(0)

                    HistoryView()
                        .environment(appState)
                        .tabItem {
                            Image(systemName: "clock.fill")
                            Text("히스토리")
                        }
                        .tag(1)

                    PlaceDiscoverView()
                        .environment(appState)
                        .tabItem {
                            Image(systemName: "fork.knife")
                            Text("주변")
                        }
                        .tag(2)

                    SettingsView()
                        .environment(appState)
                        .tabItem {
                            Image(systemName: "gearshape.fill")
                            Text("설정")
                        }
                        .tag(3)
                }
                .tint(AppColors.primary)
                .task {
                    await appState.loadHomeData()
                    consumeDeepLinkInbox()
                }
                .onChange(of: selectedTab) { _, newTab in
                    // 홈(0) / 히스토리(1) 진입 시 최신 데이터 재조회
                    if newTab == 0 || newTab == 1 {
                        Task { await appState.loadHomeData() }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .refreshFamilyData)) { _ in
                    Task { await appState.loadHomeData() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .deepLinkReceived)) { _ in
                    consumeDeepLinkInbox()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await appState.loadHomeData() }
                    }
                }
            }
        }
    }

    /// 정적 인박스에 쌓인 deep-link을 AppState로 옮기고, 해당 탭으로 전환.
    /// 콜드 스타트(.task)와 포그라운드 알림 탭(NotificationCenter) 양쪽에서 호출.
    private func consumeDeepLinkInbox() {
        guard let link = DeepLinkInbox.pending else { return }
        DeepLinkInbox.pending = nil
        appState.pendingDeepLink = link
        let targetTab: Int
        switch link {
        case .meetingComment, .meetingAttendance: targetTab = 0
        case .meetingRecord: targetTab = 1
        }
        if selectedTab != targetTab {
            selectedTab = targetTab
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
