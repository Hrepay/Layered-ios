import SwiftUI
import LinkPresentation

struct HomeView: View {
    var family: Family
    var members: [Member]
    var meetings: [Meeting]
    var currentUser: User

    @Environment(AppState.self) private var appState: AppState

    @State private var showMeetingDetail: Meeting?
    @State private var showCreateMeeting = false
    @State private var showCreateRecord: Meeting?
    @State private var showInvite = false
    @State private var toast: ToastData?
    @State private var dismissedRecordCard = false
    @State private var meetingLinkMetadata: LPLinkMetadata?
    /// detail을 다른 모임으로 교체할 때 dismiss → present 사이의 일시적 nil 상태에서
    /// 새 모임을 보관해 뒀다가 dismiss 콜백 후 다시 띄움.
    @State private var queuedDetailMeeting: Meeting?

    private var currentPlanner: Member? {
        guard !members.isEmpty,
              family.currentPlannerIndex < members.count else { return nil }
        return members[family.currentPlannerIndex]
    }

    private var isPlanner: Bool {
        currentPlanner?.id == currentUser.id
    }

    private var upcomingMeeting: Meeting? {
        meetings.first {
            ($0.status == .confirmed || $0.status == .planning)
            && $0.meetingDate > Date()
        }
    }

    private var pastMeeting: Meeting? {
        meetings.first {
            $0.meetingDate <= Date()
            && $0.status != .cancelled
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(family.name) 가족")
                            .font(.largeTitle)
                            .bold()
                        Text("우리 가족의 소중한 겹겹의 기록")
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)

                    if members.count <= 1 {
                        invitePromptCard
                    }

                    plannerSection

                    if let meeting = upcomingMeeting {
                        dDayCard(meeting)

                        Button {
                            Haptic.light()
                            showMeetingDetail = meeting
                        } label: {
                            meetingCard(meeting)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // 지난 모임 기록 카드
                        if let past = pastMeeting,
                           !dismissedRecordCard,
                           !appState.myRecordedMeetingIds.contains(past.id) {
                            recordPromptCard(past)
                        }

                        // 모임 추가하기 카드
                        if isPlanner {
                            addMeetingCard
                        } else {
                            // 비-플래너는 다가오는 모임이 없으면 지난 모임 유무와 무관하게
                            // "다음 플래너를 기다려주세요" 카드를 노출한다.
                            emptyMeetingView
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .refreshable {
                await appState.loadHomeData()
            }
            .toast($toast)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(upcomingMeeting?.id ?? "")|\(upcomingMeeting?.placeURL ?? "")") {
                meetingLinkMetadata = nil
                guard let urlString = upcomingMeeting?.placeURL else { return }
                #if DEBUG
                if AppState.useMockForScreenshots {
                    meetingLinkMetadata = MockLinkMetadata.hangang(
                        urlString: urlString,
                        title: upcomingMeeting?.place ?? "한강공원"
                    )
                    return
                }
                #endif
                if let url = URL(string: urlString) {
                    let provider = LPMetadataProvider()
                    if let metadata = try? await provider.startFetchingMetadata(for: url) {
                        meetingLinkMetadata = metadata
                    }
                }
            }
            .fullScreenCover(item: $showMeetingDetail, onDismiss: {
                // detail 교체 케이스: dismiss 후 큐잉된 모임을 다시 띄움.
                if let queued = queuedDetailMeeting {
                    queuedDetailMeeting = nil
                    showMeetingDetail = queued
                }
            }) { meeting in
                NavigationStack {
                    MeetingDetailView(meeting: meeting, onBack: {
                        showMeetingDetail = nil
                    }, onDeleted: {
                        showMeetingDetail = nil
                        Task { await appState.refreshMeetings() }
                    }, onUpdated: {
                        Task { await appState.refreshMeetings() }
                    })
                    .environment(appState)
                }
                .errorAlert(Bindable(appState).error)
            }
            .onChange(of: appState.pendingDeepLink) { _, link in
                handleDeepLink(link)
            }
            .task {
                handleDeepLink(appState.pendingDeepLink)
            }
            .fullScreenCover(isPresented: $showCreateMeeting) {
                CreateMeetingView(onBack: {
                    showCreateMeeting = false
                }, onCreated: { meeting, poll in
                    showCreateMeeting = false
                    Task {
                        do {
                            let created = try await appState.createMeeting(meeting)
                            if let poll {
                                _ = try await appState.createPoll(meetingId: created.id, poll: poll)
                            }
                        } catch {
                            appState.error = AppError.from(error)
                        }
                    }
                })
                .environment(appState)
            }
            .fullScreenCover(item: $showCreateRecord) { meeting in
                CreateRecordView(meeting: meeting, onBack: {
                    showCreateRecord = nil
                }, onSaved: { _ in
                    showCreateRecord = nil
                    Task {
                        await appState.checkMyRecords()
                        toast = ToastData(type: .success, message: "기록이 저장되었습니다")
                    }
                })
                .environment(appState)
            }
            .fullScreenCover(isPresented: $showInvite) {
                InviteMemberView(onBack: { showInvite = false })
                    .environment(appState)
            }
        }
    }

    // MARK: - 플래너 섹션
    /// 플래너가 바뀌면 아바타·이름이 좌→우로 슬라이드하면서 교체된다 ("바통 터치").
    /// 트랜지션을 켜기 위해 내용 컨테이너에 `.id(currentPlanner?.id)`를 걸어
    /// 플래너 변경 시 자연스럽게 unmount → mount가 일어나도록 한다.
    private var plannerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                AvatarView(
                    name: currentPlanner?.name ?? "?",
                    size: 52,
                    imageURL: currentPlanner?.profileImageURL
                )
                .id(currentPlanner?.id ?? "none")
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("THIS WEEK'S PLANNER")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                ZStack {
                    if isPlanner {
                        Text("이번 주 플래너는 나!")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    } else {
                        Text("이번 주 플래너는 \(currentPlanner?.name ?? "미정")!")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
                .id(currentPlanner?.id ?? "none")
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(.spring(duration: 0.55, bounce: 0.35), value: currentPlanner?.id)
        .onChange(of: currentPlanner?.id) { _, _ in
            Haptic.medium()
        }
        .liquidGlassCard(highlighted: true)
    }

    // MARK: - D-Day 카드
    /// iOS 26+에서는 Liquid Glass로 띄우고, 그 이하 버전은 기존 피치 톤 배경 유지.
    @ViewBuilder
    private func dDayCard(_ meeting: Meeting) -> some View {
        let content = VStack(spacing: 8) {
            Text(dDayText(for: meeting.meetingDate))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.primary)

            Text("다음 모임까지")
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(AppColors.primaryLight),
                    in: RoundedRectangle(cornerRadius: 20)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(AppColors.primaryLight)
                        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
                )
        }
    }

    // MARK: - 모임 카드
    private func meetingCard(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 링크 미리보기 이미지 (패딩 밖, 카드 상단에 꽉 차게)
            if meetingLinkMetadata != nil || meeting.placeURL != nil {
                ZStack(alignment: .topLeading) {
                    if let metadata = meetingLinkMetadata {
                        LinkPreviewImage(metadata: metadata)
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .allowsHitTesting(false)
                    }

                    // 상태 뱃지 (이미지 위에 오버레이)
                    HStack(spacing: 6) {
                        BadgeView(
                            text: meeting.status == .confirmed ? "확정" : "예정됨",
                            color: meeting.status == .confirmed ? AppColors.secondary : AppColors.warning
                        )
                        if meeting.hasPoll {
                            BadgeView(text: "투표", color: AppColors.info)
                        }
                    }
                    .padding(12)
                }
            }

            // 하단 콘텐츠 (패딩 적용)
            VStack(alignment: .leading, spacing: 0) {
                // 이미지 없을 때 뱃지
                if meetingLinkMetadata == nil && meeting.placeURL == nil {
                    HStack {
                        BadgeView(
                            text: meeting.status == .confirmed ? "확정" : "예정됨",
                            color: meeting.status == .confirmed ? AppColors.secondary : AppColors.warning
                        )
                        if meeting.hasPoll {
                            BadgeView(text: "투표", color: AppColors.info)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 14)
                } else {
                    Spacer().frame(height: 14)
                }

                // 날짜
                Text(formatDate(meeting.meetingDate))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color(hex: "6B3A2A"))
                    .padding(.bottom, 6)

                // 장소 + 활동 아이콘들
                HStack(alignment: .top) {
                    Text(meeting.displayPlace)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Spacer()

                    if let activity = meeting.activity {
                        HStack(spacing: 6) {
                            ForEach(activityIcons(for: activity), id: \.self) { iconName in
                                Image(systemName: iconName)
                                    .font(.title3)
                                    .foregroundStyle(AppColors.primary)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)

                // 활동 내용
                if let activity = meeting.activity {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(activity)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 16)
                }

                // 하단: 멤버 아바타 + 상세 정보
                HStack {
                    HStack(spacing: -8) {
                        ForEach(members.prefix(4)) { member in
                            AvatarView(name: member.name, size: 32, imageURL: member.profileImageURL)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                        if members.count > 4 {
                            Text("+\(members.count - 4)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("상세 정보")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.primary)
                }

            }
            .padding(.horizontal, 16)
            .padding(.top, meetingLinkMetadata == nil && meeting.placeURL == nil ? 16 : 0)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemGray6))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // 활동 문자열에서 매칭되는 아이콘들 모두 반환
    private func activityIcons(for activity: String) -> [String] {
        let iconMap: [(String, String)] = [
            ("외식", "fork.knife"),
            ("카페", "cup.and.saucer.fill"),
            ("영화", "film.fill"),
            ("산책", "figure.walk"),
            ("운동", "figure.run"),
            ("피크닉", "leaf.fill"),
            ("쇼핑", "cart.fill"),
            ("집에서", "house.fill"),
            ("게임", "gamecontroller.fill"),
            ("문화생활", "book.fill"),
        ]
        var icons: [String] = []
        for (keyword, icon) in iconMap {
            if activity.contains(keyword) {
                icons.append(icon)
            }
        }
        return icons.isEmpty ? ["figure.walk"] : icons
    }

    // MARK: - 모임 기록 유도 카드
    private func recordPromptCard(_ meeting: Meeting) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.primary)

            Text("모임은 어떠셨나요?")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("\(meeting.displayPlace)에서의 모임을 기록해보세요")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: {
                Haptic.light()
                showCreateRecord = meeting
            }) {
                Text("기록하기")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            Button {
                Haptic.light()
                withAnimation(.spring(duration: 0.25)) {
                    dismissedRecordCard = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
            }
            .padding(4)
        }
        .card()
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - 모임 추가하기 카드
    private var addMeetingCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.primary)

            Text("새 모임을 계획해보세요")
                .font(.headline)
                .foregroundStyle(.primary)

            Button(action: {
                Haptic.medium()
                showCreateMeeting = true
            }) {
                Text("모임 계획하기")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .card()
    }

    // MARK: - 빈 상태
    private var emptyMeetingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.primary)

            if isPlanner {
                Text("이번 주 모임을 계획해보세요")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Button(action: {
                    Haptic.medium()
                    showCreateMeeting = true
                }) {
                    Text("모임 계획하기")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                }
            } else {
                Text("아직 이번 주 모임이 등록되지 않았어요")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("플래너가 모임을 준비 중이에요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .card()
    }

    // MARK: - 초대 유도 카드
    private var invitePromptCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.primary)

            Text("가족을 초대해보세요!")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("초대 코드를 공유하여 가족 구성원을 추가하세요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                Haptic.medium()
                showInvite = true
            }) {
                Text("초대하기")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .card(highlighted: true)
    }

    // MARK: - Deep Link
    /// 푸시로 들어온 deep-link 라우팅.
    /// - 작성 모달이 떠 있으면 사용자 작업 보호를 위해 무시(드랍).
    /// - 같은 모임 detail이 이미 떠 있으면 MeetingDetailView가 알아서 처리하므로 패스.
    /// - 다른 모임 detail이면 닫고 다시 띄우는 큐잉, 없으면 바로 띄움.
    /// - 로컬에 없는 모임이면 단건 fetch 후 띄움.
    private func handleDeepLink(_ link: DeepLink?) {
        guard let link else { return }

        if showCreateMeeting || showCreateRecord != nil || showInvite {
            appState.pendingDeepLink = nil
            return
        }

        switch link {
        case .meetingComment(let meetingId), .meetingAttendance(let meetingId):
            if let detail = showMeetingDetail, detail.id == meetingId {
                return
            }
            Task {
                let target = await resolveMeeting(id: meetingId)
                guard let meeting = target else {
                    appState.pendingDeepLink = nil
                    return
                }
                if showMeetingDetail != nil {
                    queuedDetailMeeting = meeting
                    showMeetingDetail = nil
                } else {
                    showMeetingDetail = meeting
                }
            }
        case .meetingRecord:
            // 히스토리 탭(HistoryView)이 처리하므로 홈에서는 무시
            return
        }
    }

    private func resolveMeeting(id: String) async -> Meeting? {
        if let m = appState.meetings.first(where: { $0.id == id }) { return m }
        guard let familyId = appState.currentFamily?.id else { return nil }
        return try? await appState.meetingRepository.getMeeting(familyId: familyId, meetingId: id)
    }

    // MARK: - Helpers
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppColors.primary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private func dDayText(for date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days == 0 { return "D-Day" }
        if days > 0 { return "D-\(days)" }
        return "D+\(abs(days))"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E) a h:mm"
        return formatter.string(from: date)
    }
}

#Preview("모임 있음") {
    HomeView(
        family: MockData.family,
        members: MockData.members,
        meetings: MockData.meetings,
        currentUser: MockData.currentUser
    )
    .environment(AppState())
}

#Preview("모임 없음 - 플래너") {
    HomeView(
        family: MockData.family,
        members: MockData.members,
        meetings: [],
        currentUser: MockData.currentUser
    )
    .environment(AppState())
}

#Preview("모임 없음 - 비플래너") {
    HomeView(
        family: Family(
            id: "family-001", name: "황씨네", inviteCode: "ABC123",
            inviteCodeExpiresAt: Date(), adminId: "user-002",
            memberCount: 3, currentPlannerIndex: 1, rotationDay: 1, rotationMode: "auto", createdAt: Date()
        ),
        members: MockData.members,
        meetings: [],
        currentUser: MockData.currentUser
    )
    .environment(AppState())
}

#Preview("구성원 본인만 - 초대 유도") {
    HomeView(
        family: MockData.family,
        members: [MockData.members[0]],
        meetings: [],
        currentUser: MockData.currentUser
    )
    .environment(AppState())
}

#Preview("모임 완료 - 기록 유도") {
    HomeView(
        family: MockData.family,
        members: MockData.members,
        meetings: [MockData.meetings[1]],
        currentUser: MockData.currentUser
    )
    .environment(AppState())
}

/// 플래너 바통 터치 트랜지션을 프리뷰에서 직접 트리거.
/// 하단의 "다음 플래너로" 버튼을 누르면 currentPlannerIndex가 순환하면서 슬라이드 트랜지션이 발화.
#Preview("플래너 바통 터치 데모") {
    HomePlannerTransitionDemo()
}

private struct HomePlannerTransitionDemo: View {
    @State private var family = MockData.family
    private let members = MockData.members

    var body: some View {
        VStack(spacing: 0) {
            HomeView(
                family: family,
                members: members,
                meetings: MockData.meetings,
                currentUser: MockData.currentUser
            )
            .environment(AppState())

            Button {
                family.currentPlannerIndex = (family.currentPlannerIndex + 1) % max(members.count, 1)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("다음 플래너로 (\(members[(family.currentPlannerIndex + 1) % members.count].name))")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(AppColors.primary)
                .clipShape(Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .buttonStyle(.plain)
        }
    }
}
