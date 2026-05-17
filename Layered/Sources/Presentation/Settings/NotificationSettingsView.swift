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
    @State private var meetingComment = true
    @State private var meetingRecord = true
    @State private var meetingDDay = true
    @State private var nudge = true
    @State private var isLoaded = false

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
            meetingComment = settings.meetingComment
            meetingRecord = settings.meetingRecord
            meetingDDay = settings.meetingDDay
            nudge = settings.nudge
            isLoaded = true
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
}

#Preview {
    NotificationSettingsView(onBack: {})
}
