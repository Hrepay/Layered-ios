import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState: AppState

    @State private var showProfileEdit = false
    @State private var refreshId = UUID()
    @State private var showMemberList = false
    @State private var showInvite = false
    @State private var showRotation = false
    @State private var showNotification = false
    @State private var showAccount = false
    @State private var showFamilyManagement = false
    @State private var legalURL: URL?
    @State private var appStoreVersion: String?

    private var displayedVersion: String {
        if let appStoreVersion { return "v\(appStoreVersion)" }
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(bundleVersion)"
    }

    /// 현재 사용자가 가족에 합류한 지 며칠 됐는지. 본인 멤버 객체가 없거나 미가입이면 nil.
    private var daysWithFamily: Int? {
        guard let userId = appState.currentUser?.id,
              let me = appState.members.first(where: { $0.id == userId }) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: me.joinedAt, to: Date()).day ?? 0
        return max(days, 1) // 같은 날 합류해도 "1일째"로 표현
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - 프로필 헤더
                VStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(
                            name: appState.currentUser?.name ?? "사용자",
                            size: 100,
                            imageURL: appState.currentUser?.profileImageURL
                        )

                        Button {
                            Haptic.light()
                            showProfileEdit = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color(.systemGray))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }

                    Text(appState.currentUser?.name ?? "사용자")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(appState.currentFamily?.name ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // MARK: - 함께한 지 N일째 (가운데 정렬, 가벼운 라인)
                if let daysWithFamily {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(AppColors.primary)
                        Text("겹겹과 함께한 지 \(daysWithFamily)일째")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // MARK: - 상단 2열 카드
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FAMILY MEMBERS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text("가족")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        Text("\(appState.members.count)명")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // 플래너 카드만 정체성 컬러 유지(피치 배경 + 흰 글씨) — 글래스 X
                    VStack(alignment: .leading, spacing: 6) {
                        Text("THIS WEEK")
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text("플래너")
                            .font(.title3).fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text(currentPlannerName)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(AppColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .fixedSize(horizontal: false, vertical: true)

                // MARK: - 가정 관리 (그룹 카드)
                VStack(alignment: .leading, spacing: 8) {
                    Text("가정 관리")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        groupedRow(
                            icon: "person.crop.circle.fill",
                            title: "구성원 목록",
                            accessory: { AnyView(memberAvatarStack) }
                        ) { showMemberList = true }
                        Divider().padding(.leading, 66)
                        groupedRow(icon: "person.badge.plus.fill", title: "초대하기") { showInvite = true }
                        Divider().padding(.leading, 66)
                        groupedRow(icon: "arrow.triangle.2.circlepath", title: "플래너 설정") { showRotation = true }
                        Divider().padding(.leading, 66)
                        groupedRow(icon: "house.fill", title: "가정 관리") { showFamilyManagement = true }
                    }
                    .glassGroupedBackground()
                }

                // MARK: - 앱 설정 (그룹 카드)
                VStack(alignment: .leading, spacing: 8) {
                    Text("앱 설정")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        groupedRow(icon: "bell.fill", title: "알림 설정") { showNotification = true }
                        Divider().padding(.leading, 66)
                        groupedRow(icon: "info.circle.fill", title: "버전 정보", trailing: displayedVersion) {}
                    }
                    .glassGroupedBackground()
                }

                // MARK: - 약관 및 정책
                VStack(alignment: .leading, spacing: 8) {
                    Text("약관 및 정책")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        groupedRow(icon: "doc.text.fill", title: "이용약관") {
                            legalURL = AppConstants.Legal.termsURL
                        }
                        Divider().padding(.leading, 66)
                        groupedRow(icon: "hand.raised.fill", title: "개인정보 처리방침") {
                            legalURL = AppConstants.Legal.privacyURL
                        }
                        Divider().padding(.leading, 66)
                        groupedRow(icon: "megaphone.fill", title: "마케팅 정보 수신 동의") {
                            legalURL = AppConstants.Legal.marketingURL
                        }
                    }
                    .glassGroupedBackground()
                }

                // MARK: - 계정 관리
                Button {
                    Haptic.light()
                    showAccount = true
                } label: {
                    Text("계정 관리")
                        .font(.subheadline)
                        .foregroundStyle(Color(.darkGray))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
        }
        .id(refreshId)
        .task {
            await fetchAppStoreVersion()
        }
        .fullScreenCover(isPresented: $showProfileEdit) {
            ProfileEditView(onBack: {
                showProfileEdit = false
                refreshId = UUID()
            })
            .environment(appState)
        }
        .fullScreenCover(isPresented: $showMemberList) {
            MemberListView(onBack: { showMemberList = false })
                .environment(appState)
        }
        .fullScreenCover(isPresented: $showInvite) {
            InviteMemberView(onBack: { showInvite = false })
                .environment(appState)
        }
        .fullScreenCover(isPresented: $showRotation) {
            RotationOrderView(onBack: { showRotation = false })
                .environment(appState)
        }
        .fullScreenCover(isPresented: $showNotification) {
            NotificationSettingsView(onBack: { showNotification = false })
        }
        .fullScreenCover(isPresented: $showAccount) {
            AccountView(onBack: { showAccount = false })
                .environment(appState)
        }
        .fullScreenCover(isPresented: $showFamilyManagement) {
            FamilyManagementView(onBack: { showFamilyManagement = false })
                .environment(appState)
        }
        .sheet(item: Binding(
            get: { legalURL.map { LegalURLItem(url: $0) } },
            set: { legalURL = $0?.url }
        )) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }

    private func groupedRow(
        icon: String,
        title: String,
        trailing: String? = nil,
        accessory: (() -> AnyView)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptic.light()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemBackground))
                    .clipShape(Circle())

                Text(title)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                if let accessory { accessory() }
                if let trailing {
                    Text(trailing).font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 가족 멤버 아바타 미리보기 — 4명까지 stacked, 그 이상은 +N.
    private var memberAvatarStack: some View {
        HStack(spacing: -8) {
            ForEach(appState.members.prefix(4)) { member in
                AvatarView(name: member.name, size: 24, imageURL: member.profileImageURL)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
            if appState.members.count > 4 {
                Text("+\(appState.members.count - 4)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            }
        }
    }

    // MARK: - Helpers
    private var currentPlannerName: String {
        let members = appState.members
        guard let family = appState.currentFamily,
              family.currentPlannerIndex < members.count else { return "미정" }
        return members[family.currentPlannerIndex].name
    }

    @MainActor
    private func fetchAppStoreVersion() async {
        // 1시간 캐시: 설정 화면 재진입마다 네트워크 호출하지 않도록.
        let defaults = UserDefaults.standard
        let cachedVersion = defaults.string(forKey: Self.cachedVersionKey)
        let cachedAt = defaults.object(forKey: Self.cachedAtKey) as? Date
        if let cachedVersion,
           let cachedAt,
           Date().timeIntervalSince(cachedAt) < Self.cacheTTL {
            appStoreVersion = cachedVersion
            return
        }

        guard let bundleId = Bundle.main.bundleIdentifier,
              var components = URLComponents(string: "https://itunes.apple.com/lookup") else { return }
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "country", value: "kr")
        ]
        guard let url = components.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
            if let version = decoded.results.first?.version {
                appStoreVersion = version
                defaults.set(version, forKey: Self.cachedVersionKey)
                defaults.set(Date(), forKey: Self.cachedAtKey)
            }
        } catch {
            // 네트워크 실패/미배포: displayedVersion이 번들 버전으로 fallback
        }
    }

    private static let cachedVersionKey = "appStoreVersion.cached"
    private static let cachedAtKey = "appStoreVersion.cachedAt"
    private static let cacheTTL: TimeInterval = 60 * 60 // 1 hour
}

private struct ITunesLookupResponse: Decodable {
    let results: [ITunesLookupResult]
}

private struct ITunesLookupResult: Decodable {
    let version: String
}

private struct LegalURLItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#Preview {
    SettingsView()
}
