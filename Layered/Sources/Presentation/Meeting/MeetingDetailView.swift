import SwiftUI
import MapKit
import LinkPresentation

struct MeetingDetailView: View {
    @State private var meeting: Meeting
    let onBack: () -> Void
    var onDeleted: (() -> Void)?
    var onUpdated: (() -> Void)?
    var showsActionMenu: Bool = true

    @Environment(AppState.self) private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var showDeleteAlert = false
    @State private var showEdit = false
    @State private var poll: Poll?
    @State private var linkMetadata: LPLinkMetadata?
    @State private var showAddCandidate = false
    @State private var newCandidateTitle = ""
    @State private var newCandidateLink = ""
    @State private var confirmCandidateOption: PollOption?
    @State private var isMutatingPoll = false
    @State private var showDiscussion = false
    @State private var showParticipants = false
    @State private var toast: ToastData?

    init(meeting: Meeting, onBack: @escaping () -> Void, onDeleted: (() -> Void)? = nil, onUpdated: (() -> Void)? = nil, showsActionMenu: Bool = true) {
        _meeting = State(initialValue: meeting)
        self.onBack = onBack
        self.onDeleted = onDeleted
        self.onUpdated = onUpdated
        self.showsActionMenu = showsActionMenu
    }

    private var isPlanner: Bool {
        meeting.plannerId == appState.currentUser?.id
    }

    private var participantMembers: [Member] {
        let ids = meeting.effectiveParticipantIds(allMemberIds: appState.members.map(\.id))
        return appState.members.filter { ids.contains($0.id) }
    }

    private var attendanceSummaryText: String {
        let members = participantMembers
        let going = members.filter { meeting.attendanceStatus(for: $0.id) == .going }.count
        let notGoing = members.filter { meeting.attendanceStatus(for: $0.id) == .notGoing }.count
        let pending = members.count - going - notGoing
        return "확정 \(going) · 미정 \(pending) · 불참 \(notGoing)"
    }

    private func attendanceColor(for member: Member) -> Color {
        switch meeting.attendanceStatus(for: member.id) {
        case .going: return AppColors.secondary
        case .notGoing: return Color.red
        case nil: return AppColors.warning
        }
    }

    private func attendanceDot(for member: Member) -> some View {
        Circle()
            .fill(attendanceColor(for: member))
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    private var actionMenu: AnyView? {
        guard showsActionMenu else { return nil }
        return AnyView(
            Menu {
                // 모임 수정은 모든 구성원 가능 (노션 핵심 기능 명세)
                Button("수정", systemImage: "pencil") { showEdit = true }
                // 모임 삭제는 플래너 본인만
                if isPlanner {
                    Button("삭제", systemImage: "trash", role: .destructive) {
                        showDeleteAlert = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "모임 상세",
                backAction: onBack,
                trailingMenu: actionMenu
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: - 상단 헤더
                    VStack(alignment: .leading, spacing: 8) {
                        BadgeView(text: statusText, color: statusColor)

                        Text(meeting.hasPoll && meeting.place.isEmpty ? "장소 투표 중" : meeting.place)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)

                        Text(meeting.hasPoll && meeting.place.isEmpty
                             ? "가족들과 함께 갈 곳을 정해보세요."
                             : "함께 모여 따뜻한 시간을 보냅니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // MARK: - 일시 카드
                    HStack(spacing: 14) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("일시")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatDateFull(meeting.meetingDate))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatTimePeriod(meeting.meetingDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatTime(meeting.meetingDate))
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                        }
                    }
                    .card()

                    // MARK: - 장소 카드 (단일) 또는 후보 리스트 (투표 중)
                    if meeting.hasPoll && meeting.place.isEmpty {
                        candidatesCard
                    } else {
                        singlePlaceCard
                    }

                    // MARK: - 활동 & 플래너 (2열 그리드)
                    HStack(spacing: 12) {
                        // 활동
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: activityIconName)
                                .font(.title3)
                                .foregroundStyle(AppColors.primary)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())

                            Text("활동")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(meeting.activity ?? "미정")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()

                        // 플래너
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "person.fill")
                                .font(.title3)
                                .foregroundStyle(AppColors.primary)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())

                            Text("작성자")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(meeting.plannerName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    // MARK: - 참여 인원
                    let participants = participantMembers
                    if !participants.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("참여 인원 (\(participants.count)명)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(attendanceSummaryText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: -8) {
                                ForEach(participants.prefix(5)) { member in
                                    AvatarView(name: member.name, size: 36, imageURL: member.profileImageURL)
                                        .overlay(Circle().stroke(.white, lineWidth: 2))
                                        .overlay(alignment: .bottomTrailing) {
                                            attendanceDot(for: member)
                                        }
                                }
                                if participants.count > 5 {
                                    Text("+\(participants.count - 5)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, height: 36)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(.white, lineWidth: 2))
                                }
                            }
                        }
                        .card()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptic.light()
                            showParticipants = true
                        }
                    }

                    // MARK: - 장소 링크 미리보기
                    if let urlString = meeting.placeURL, let url = URL(string: urlString) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("장소 링크")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            if let metadata = linkMetadata {
                                LinkPreviewCard(metadata: metadata)
                            } else {
                                Button {
                                    Haptic.light()
                                    UIApplication.shared.open(url)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "link")
                                            .foregroundStyle(AppColors.info)
                                        Text(urlString)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .card()
                                }
                            }
                        }
                    }

                    // MARK: - 지도
                    if let lat = meeting.placeLatitude, let lng = meeting.placeLongitude {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))) {
                            Marker(meeting.place, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                                .tint(AppColors.primary)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    // MARK: - 최근 수정 — 가족 누구나 수정 가능한 정책이라 변경 출처를 명시
                    if let editorName = meeting.lastEditedByName, let editedAt = meeting.lastEditedAt {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("최근 수정 · \(editorName) · \(MeetingTimeFormat.relative(editedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .refreshable {
                await reloadDetail()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(meeting.id)|\(meeting.placeURL ?? "")") {
            linkMetadata = nil
            await reloadDetail()
        }
        .fullScreenCover(isPresented: $showEdit) {
            EditMeetingView(meeting: meeting, onBack: {
                showEdit = false
            }, onSaved: { updatedMeeting in
                // 종료/취소된 모임 → planning 으로 살아난 경우 토스트 + success 햅틱.
                // 비교 시점이 중요: meeting을 갈아끼우기 전에 이전 status를 캡처.
                let didReactivate = (meeting.status == .completed || meeting.status == .cancelled)
                    && updatedMeeting.status == .planning
                showEdit = false
                meeting = updatedMeeting
                onUpdated?()
                // EditView에서 Poll 변경이 일어났을 수 있어 다시 로드
                Task { await reloadDetail() }
                if didReactivate {
                    Haptic.success()
                    toast = ToastData(type: .success, message: "이 모임이 홈으로 돌아왔어요")
                }
            })
            .environment(appState)
        }
        .navigationDestination(isPresented: $showDiscussion) {
            MeetingDiscussionView(meeting: meeting, onBack: {
                showDiscussion = false
                Task { await reloadDetail() }
            })
            .environment(appState)
        }
        .alert("모임 삭제", isPresented: $showDeleteAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                Task {
                    do {
                        try await appState.deleteMeeting(meeting.id)
                        onDeleted?()
                    } catch {
                        appState.error = AppError.from(error)
                    }
                }
            }
        } message: {
            Text("정말 삭제하시겠습니까?\n관련 기록도 함께 삭제됩니다.")
        }
        .toast($toast)
        .alert("이 장소로 확정", isPresented: Binding(
            get: { confirmCandidateOption != nil },
            set: { if !$0 { confirmCandidateOption = nil } }
        ), presenting: confirmCandidateOption) { option in
            Button("취소", role: .cancel) { confirmCandidateOption = nil }
            Button("확정") {
                Task { await confirmCandidate(option) }
            }
        } message: { option in
            Text("'\(option.title)' 으로 모임 장소를 확정하시겠습니까?\n투표는 종료됩니다.")
        }
        .sheet(isPresented: $showAddCandidate) {
            addCandidateSheet
        }
        .fullScreenCover(isPresented: $showParticipants) {
            MeetingParticipantsView(meeting: $meeting, onBack: { showParticipants = false })
                .environment(appState)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 백그라운드에서 돌아올 때 다른 멤버의 의견/투표 자동 반영
            if newPhase == .active {
                Task { await reloadDetail() }
            }
        }
        .onChange(of: appState.pendingDeepLink) { _, link in
            consumeDeepLinkIfMatches(link)
        }
        .task {
            consumeDeepLinkIfMatches(appState.pendingDeepLink)
        }
        .swipeBack(onBack: onBack)
    }

    /// 자기 모임을 가리키는 deep-link이면 Discussion 화면으로 push.
    /// 이미 Discussion이 떠 있으면 set이 idempotent라 추가 애니메이션 없이 그대로 유지.
    private func consumeDeepLinkIfMatches(_ link: DeepLink?) {
        switch link {
        case let .meetingComment(meetingId) where meetingId == meeting.id:
            if !showDiscussion {
                showDiscussion = true
            }
            appState.pendingDeepLink = nil
        case let .meetingAttendance(meetingId) where meetingId == meeting.id:
            // 콕 찌르기 푸시 → 참석 토글이 있는 참여 인원 화면을 바로 연다.
            if !showParticipants {
                showParticipants = true
            }
            appState.pendingDeepLink = nil
        default:
            return
        }
    }

    // MARK: - 단일 장소 카드 (탭 → Discussion)

    @ViewBuilder
    private var singlePlaceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(AppColors.primary)
                .frame(width: 44, height: 44)
                .background(Color(.systemBackground))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("장소")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(meeting.place)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.light()
            showDiscussion = true
        }
    }

    // MARK: - 후보 카드 (투표 모드)

    @ViewBuilder
    private var candidatesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("장소 후보")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                if let poll {
                    Text("\(poll.options.count)곳")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let poll {
                let maxVotes = poll.options.map(\.voteCount).max() ?? 0
                let totalVotes = poll.options.reduce(0) { $0 + $1.voteCount }

                ForEach(poll.options) { option in
                    candidateRow(option: option, maxVotes: maxVotes, totalVotes: totalVotes)
                }

                if isPlanner && poll.options.count < 4 {
                    Button {
                        Haptic.light()
                        newCandidateTitle = ""
                        newCandidateLink = ""
                        showAddCandidate = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("후보 추가")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppColors.primarySubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isMutatingPoll)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("후보 불러오는 중...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.light()
            showDiscussion = true
        }
    }

    @ViewBuilder
    private func candidateRow(option: PollOption, maxVotes: Int, totalVotes: Int) -> some View {
        let isWinner = option.voteCount == maxVotes && maxVotes > 0
        VStack(alignment: .leading, spacing: 10) {
            // 상단: 제목 + (오른쪽 끝) 링크
            HStack(spacing: 8) {
                Text(option.title)
                    .font(.subheadline)
                    .fontWeight(isWinner ? .bold : .medium)
                    .foregroundStyle(.primary)
                Spacer()
                if let urlString = option.linkURL, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Image(systemName: "link")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(AppColors.primarySubtle))
                    }
                }
            }

            // 하단: 바 + 표수 + 확정
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isWinner ? AppColors.primary : Color(.systemGray3))
                            .frame(
                                width: totalVotes > 0
                                    ? geo.size.width * CGFloat(option.voteCount) / CGFloat(totalVotes)
                                    : 0,
                                height: 6
                            )
                            .animation(.spring(duration: 0.4), value: option.voteCount)
                    }
                }
                .frame(height: 6)

                Text("\(option.voteCount)표")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isWinner ? AppColors.primary : .secondary)

                if isPlanner {
                    Button {
                        Haptic.light()
                        confirmCandidateOption = option
                    } label: {
                        Text("확정")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColors.primary)
                            .clipShape(Capsule())
                    }
                    .disabled(isMutatingPoll)
                }
            }

            // 투표자 표시 — 공개 투표일 때만 (현재 EditMeetingView에서 만든 Poll은 항상 비-익명).
            // 멤버 아바타를 스택으로 보여줘서 "누가 골랐는지" 한눈에 확인.
            if let poll, !poll.isAnonymous, !option.voterIds.isEmpty {
                voterAvatars(for: option)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isWinner ? AppColors.primary.opacity(0.4) : Color(.systemGray5), lineWidth: 1)
        )
    }

    // MARK: - 투표자 아바타

    /// 옵션에 투표한 멤버들을 작은 아바타 스택으로 표시.
    /// 실제 렌더링은 공통 컴포넌트 PollVoterAvatars로 위임 — MeetingDiscussionView와 디자인 공유.
    @ViewBuilder
    private func voterAvatars(for option: PollOption) -> some View {
        PollVoterAvatars(voterIds: option.voterIds, members: appState.members)
    }

    // MARK: - 후보 추가 시트

    @ViewBuilder
    private var addCandidateSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AppTextField(placeholder: "장소명", text: $newCandidateTitle)
                AppTextField(placeholder: "링크 (선택)", text: $newCandidateLink)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .onChange(of: newCandidateLink) { _, newValue in
                        if let extracted = URLExtractor.firstURL(in: newValue),
                           extracted.absoluteString != newValue {
                            newCandidateLink = extracted.absoluteString
                        }
                    }
                Spacer()
            }
            .padding(20)
            .navigationTitle("후보 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { showAddCandidate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") {
                        Task { await addCandidate() }
                    }
                    .disabled(newCandidateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isMutatingPoll)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Poll mutation actions

    @MainActor
    private func confirmCandidate(_ option: PollOption) async {
        guard let pollId = poll?.id else { return }
        isMutatingPoll = true
        defer { isMutatingPoll = false }

        var updated = meeting
        updated.place = option.title
        updated.placeURL = option.linkURL
        updated.placeLatitude = nil
        updated.placeLongitude = nil
        updated.status = .confirmed
        updated.hasPoll = false
        updated.updatedAt = Date()

        do {
            try await appState.updateMeeting(updated)
            try? await appState.deletePoll(meetingId: meeting.id, pollId: pollId)
            meeting = updated
            poll = nil
            confirmCandidateOption = nil
            onUpdated?()
        } catch {
            appState.error = AppError.from(error)
        }
    }

    @MainActor
    private func addCandidate() async {
        guard let pollId = poll?.id else { return }
        let title = newCandidateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isMutatingPoll = true
        defer { isMutatingPoll = false }

        let linkURL = URLExtractor.firstURL(in: newCandidateLink)?.absoluteString
        let option = PollOption(
            id: UUID().uuidString,
            title: title,
            description: nil,
            imageURL: nil,
            linkURL: linkURL,
            voterIds: [],
            voteCount: 0
        )
        do {
            try await appState.addPollOption(meetingId: meeting.id, pollId: pollId, option: option)
            showAddCandidate = false
            await reloadDetail()
        } catch {
            appState.error = AppError.from(error)
        }
    }

    // MARK: - Computed

    private var statusText: String {
        switch meeting.status {
        case .planning: return "예정된 모임"
        case .confirmed: return "확정된 모임"
        case .completed: return "완료된 모임"
        case .cancelled: return "취소된 모임"
        }
    }

    private var statusColor: Color {
        switch meeting.status {
        case .planning: return AppColors.warning
        case .confirmed: return AppColors.secondary
        case .completed: return Color.gray
        case .cancelled: return Color.red
        }
    }

    private var activityIconName: String {
        guard let activity = meeting.activity else { return "figure.walk" }
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
        for (keyword, icon) in iconMap {
            if activity.contains(keyword) { return icon }
        }
        return "figure.walk"
    }

    // MARK: - Helpers

    private func reloadDetail() async {
        if meeting.hasPoll {
            let polls = try? await appState.getPolls(meetingId: meeting.id)
            poll = polls?.first
        } else {
            poll = nil
        }
        guard let urlString = meeting.placeURL else { return }
        #if DEBUG
        if AppState.useMockForScreenshots {
            linkMetadata = MockLinkMetadata.hangang(urlString: urlString, title: meeting.place)
            return
        }
        #endif
        if let url = URL(string: urlString) {
            let provider = LPMetadataProvider()
            if let metadata = try? await provider.startFetchingMetadata(for: url) {
                linkMetadata = metadata
            }
        }
    }

    private func formatDateFull(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 (E)"
        return formatter.string(from: date)
    }

    private func formatTimePeriod(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "h:mm"
        return formatter.string(from: date)
    }
}

#Preview("확정된 모임") {
    NavigationStack {
        MeetingDetailView(meeting: MockData.meetings[0], onBack: {})
            .environment(AppState())
    }
}

#Preview("완료된 모임") {
    NavigationStack {
        MeetingDetailView(meeting: MockData.meetings[1], onBack: {})
            .environment(AppState())
    }
}
