import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    let onBack: () -> Void
    @Environment(AppState.self) private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var systemAuthorized = true
    @State private var notificationsEnabled = true
    @State private var plannerReminder = true
    @State private var meetingCreated = true
    @State private var meetingUpdated = true
    @State private var meetingComment = true
    @State private var meetingRecord = true
    @State private var meetingDDay = true
    @State private var nudge = true
    @State private var isLoaded = false

    // iOS 캘린더 동기화 (UserDefaults 기반 per-device 토글)
    @State private var calendarSyncOn = false
    @State private var showCalendarPermissionAlert = false
    @State private var calendarSyncBusy = false
    @State private var showCalendarOffDialog = false

    private var masterEnabled: Bool {
        systemAuthorized && notificationsEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "알림 설정", backAction: onBack)

            List {
                if !systemAuthorized {
                    Section {
                        Button {
                            Haptic.light()
                            openSystemSettings()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppColors.warning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("iOS 알림이 꺼져있어요")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Text("알림을 받으려면 설정에서 허용해주세요")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Toggle("앱 알림 받기", isOn: Binding(
                        get: { masterEnabled },
                        set: { newValue in
                            if !systemAuthorized {
                                openSystemSettings()
                            } else {
                                notificationsEnabled = newValue
                                save()
                            }
                        }
                    ))
                    .tint(AppColors.primary)
                } footer: {
                    Text(systemAuthorized
                         ? "끄면 겹겹에서 오는 모든 알림이 중단됩니다."
                         : "iOS 시스템 설정에서 알림을 허용해주세요.")
                        .font(.caption)
                }

                Section("알림 종류") {
                    Toggle("플래너 리마인드", isOn: $plannerReminder)
                        .tint(AppColors.primary)
                        .onChange(of: plannerReminder) { _, _ in save() }

                    Toggle("모임 등록", isOn: $meetingCreated)
                        .tint(AppColors.primary)
                        .onChange(of: meetingCreated) { _, _ in save() }

                    Toggle("모임 정보 변경", isOn: $meetingUpdated)
                        .tint(AppColors.primary)
                        .onChange(of: meetingUpdated) { _, _ in save() }

                    Toggle("모임 의견", isOn: $meetingComment)
                        .tint(AppColors.primary)
                        .onChange(of: meetingComment) { _, _ in save() }

                    Toggle("모임 후기", isOn: $meetingRecord)
                        .tint(AppColors.primary)
                        .onChange(of: meetingRecord) { _, _ in save() }

                    Toggle("모임 당일 알림", isOn: $meetingDDay)
                        .tint(AppColors.primary)
                        .onChange(of: meetingDDay) { _, _ in save() }

                    Toggle("콕 찌르기", isOn: $nudge)
                        .tint(AppColors.primary)
                        .onChange(of: nudge) { _, _ in save() }
                }
                .disabled(!masterEnabled)

                Section {
                    Toggle("iOS 캘린더 동기화", isOn: Binding(
                        get: { calendarSyncOn },
                        set: { handleCalendarToggle($0) }
                    ))
                    .tint(AppColors.primary)
                    .disabled(calendarSyncBusy)
                } header: {
                    Text("기기 동기화")
                } footer: {
                    Text("가족 모임을 본인 폰의 iOS 캘린더에 자동으로 등록·갱신해요. 시작 1시간 전 시스템 알림으로 알려드려요. 가족 멤버 각자 본인 폰에서 켜야 본인 캘린더에 추가돼요.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
        }
        .task {
            await refreshPermissionStatus()
            guard !isLoaded else { return }
            let settings = await appState.loadNotificationSettings()
            notificationsEnabled = settings.enabled
            plannerReminder = settings.plannerReminder
            meetingCreated = settings.meetingCreated
            meetingUpdated = settings.meetingUpdated
            meetingComment = settings.meetingComment
            meetingRecord = settings.meetingRecord
            meetingDDay = settings.meetingDDay
            nudge = settings.nudge
            // 캘린더 토글 — 권한과 UserDefaults 둘 다 ON이어야 ON으로 표시
            calendarSyncOn = CalendarSyncService.shared.isEnabled
                && CalendarSyncService.shared.hasAccess
            isLoaded = true
        }
        .confirmationDialog(
            "겹겹이 등록한 캘린더 일정을 삭제할까요?",
            isPresented: $showCalendarOffDialog,
            titleVisibility: .visible
        ) {
            Button("일정 삭제", role: .destructive) {
                CalendarSyncService.shared.purgeAllEvents()
            }
            Button("일정 유지", role: .cancel) {}
        } message: {
            Text("동기화를 꺼도 이미 등록된 일정은 남습니다. 삭제를 선택하면 겹겹이 만든 일정만 캘린더에서 제거돼요.")
        }
        .alert("캘린더 권한이 필요해요", isPresented: $showCalendarPermissionAlert) {
            Button("취소", role: .cancel) {}
            Button("설정 열기") { openSystemSettings() }
        } message: {
            Text("iOS 설정에서 겹겹의 캘린더 접근 권한을 허용해주세요.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refreshPermissionStatus() }
            }
        }
        .swipeBack(onBack: onBack)
    }

    private func save() {
        guard isLoaded else { return }
        Task {
            await appState.updateNotificationSettings(
                NotificationSettings(
                    enabled: notificationsEnabled,
                    plannerReminder: plannerReminder,
                    meetingCreated: meetingCreated,
                    meetingUpdated: meetingUpdated,
                    meetingComment: meetingComment,
                    meetingRecord: meetingRecord,
                    meetingDDay: meetingDDay,
                    nudge: nudge
                )
            )
        }
    }

    private func refreshPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = settings.authorizationStatus == .authorized ||
                         settings.authorizationStatus == .provisional
        await MainActor.run {
            systemAuthorized = authorized
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 캘린더 동기화 토글 처리.
    /// ON 시: 권한 요청 → 허용되면 UserDefaults ON + 다가오는 모임 backfill.
    /// OFF 시: UserDefaults OFF + 등록된 일정 삭제 여부를 사용자에게 확인.
    private func handleCalendarToggle(_ newValue: Bool) {
        Haptic.light()
        if newValue {
            calendarSyncBusy = true
            Task {
                let granted = await CalendarSyncService.shared.requestAccess()
                await MainActor.run {
                    if granted {
                        CalendarSyncService.shared.isEnabled = true
                        calendarSyncOn = true
                        appState.backfillCalendarIfNeeded()
                    } else {
                        // 권한 거부 또는 시스템 설정에서 막힌 경우
                        CalendarSyncService.shared.isEnabled = false
                        calendarSyncOn = false
                        showCalendarPermissionAlert = true
                    }
                    calendarSyncBusy = false
                }
            }
        } else {
            CalendarSyncService.shared.isEnabled = false
            calendarSyncOn = false
            showCalendarOffDialog = true
        }
    }
}

#Preview {
    NotificationSettingsView(onBack: {})
}
