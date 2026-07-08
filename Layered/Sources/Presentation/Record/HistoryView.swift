import SwiftUI

/// 타임라인 한 행 — 모임 또는 한 겹(노트). 날짜순 통합 정렬을 위한 래퍼.
enum HistoryEntry: Identifiable {
    case meeting(Meeting)
    case note(Note)

    var id: String {
        switch self {
        case .meeting(let m): return "m-\(m.id)"
        case .note(let n): return "n-\(n.id)"
        }
    }

    var date: Date {
        switch self {
        case .meeting(let m): return m.meetingDate
        case .note(let n): return n.date
        }
    }
}

struct HistoryView: View {
    @Environment(AppState.self) private var appState: AppState
    @State private var selectedMeeting: Meeting?
    @State private var noteToEdit: Note?
    @State private var showCalendar = false

    private var meetings: [Meeting] { appState.meetings }
    private var notes: [Note] { appState.notes }

    /// 모임 + 노트를 날짜 desc로 통합한 엔트리. 노트는 정렬이 보장 안 될 수 있어 명시적으로 정렬.
    private var entries: [HistoryEntry] {
        let merged = meetings.map { HistoryEntry.meeting($0) } + notes.map { HistoryEntry.note($0) }
        return merged.sorted { $0.date > $1.date }
    }

    private var isEmpty: Bool { meetings.isEmpty && notes.isEmpty }

    /// 월 단위로 묶은 섹션. entries가 date desc로 정렬돼 들어오므로
    /// 순차 순회하며 직전 라벨과 다르면 새 섹션을 시작하는 방식으로 충분.
    private var monthSections: [(label: String, entries: [HistoryEntry])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        var sections: [(label: String, entries: [HistoryEntry])] = []
        for entry in entries {
            let label = formatter.string(from: entry.date)
            if var last = sections.last, last.label == label {
                last.entries.append(entry)
                sections[sections.count - 1] = last
            } else {
                sections.append((label, [entry]))
            }
        }
        return sections
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("히스토리")
                                .font(.largeTitle)
                                .bold()
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        EmptyStateView(
                            icon: "clock.fill",
                            title: "아직 모임 기록이 없어요",
                            description: "첫 번째 가족 모임의 추억을 남겨보세요"
                        )
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            HStack {
                                Text("히스토리")
                                    .font(.largeTitle)
                                    .bold()
                                Spacer()
                                // 달력 모달 진입 버튼
                                Button {
                                    Haptic.light()
                                    showCalendar = true
                                } label: {
                                    Image(systemName: "calendar")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(AppColors.primary)
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(AppColors.primarySubtle))
                                }
                            }
                            .padding(.top, 12)

                            // MARK: - 통계 hero 카드
                            statHeroCard
                                .padding(.top, 4)

                            // MARK: - 함께 다닌 장소 (좌표 있는 모임만)
                            PlacesMiniMap(meetings: meetings)

                            // MARK: - 활동 분포
                            ActivityDistributionChart(meetings: meetings)

                            // MARK: - 타임라인 (월별 섹션 · 모임 + 한 겹)
                            ForEach(monthSections, id: \.label) { section in
                                monthHeader(section.label)
                                ForEach(section.entries) { entry in
                                    entryRow(entry)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .refreshable {
                        await appState.refreshMeetings()
                        await appState.refreshNotes()
                        await appState.checkMyRecords()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCalendar) {
                MeetingCalendarSheet(
                    meetings: meetings,
                    onClose: { showCalendar = false }
                )
                // 6주 풀 월(=42칸) 기준 내용물에 맞춘 높이 + 헤더·범례·여백 포함.
                .presentationDetents([.height(580), .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $selectedMeeting) { meeting in
                NavigationStack {
                    RecordDetailView(meeting: meeting, onBack: {
                        selectedMeeting = nil
                    }, onDeleted: {
                        selectedMeeting = nil
                        Task { await appState.refreshMeetings() }
                    })
                    .environment(appState)
                }
                .errorAlert(Bindable(appState).error)
            }
            .fullScreenCover(item: $noteToEdit) { note in
                NavigationStack {
                    CreateNoteView(existingNote: note, onBack: {
                        noteToEdit = nil
                    }, onSaved: { _ in
                        noteToEdit = nil
                    })
                    .environment(appState)
                }
                .errorAlert(Bindable(appState).error)
            }
            .onChange(of: appState.pendingDeepLink) { _, link in
                consumeDeepLinkIfMatches(link)
            }
            .task {
                consumeDeepLinkIfMatches(appState.pendingDeepLink)
            }
        }
    }

    /// 후기 알림 deep-link을 받아 해당 모임의 RecordDetailView를 띄움.
    /// MainTabView가 이미 히스토리 탭으로 전환한 상태로 들어옴.
    private func consumeDeepLinkIfMatches(_ link: DeepLink?) {
        guard case let .meetingRecord(meetingId) = link else { return }
        if let meeting = meetings.first(where: { $0.id == meetingId }) {
            if selectedMeeting?.id != meeting.id {
                selectedMeeting = meeting
            }
            appState.pendingDeepLink = nil
        } else {
            // 로컬에 없으면 단건 fetch 후 띄움
            Task {
                guard let familyId = appState.currentFamily?.id,
                      let meeting = try? await appState.meetingRepository.getMeeting(
                          familyId: familyId,
                          meetingId: meetingId
                      ) else {
                    appState.pendingDeepLink = nil
                    return
                }
                await MainActor.run {
                    if selectedMeeting?.id != meeting.id {
                        selectedMeeting = meeting
                    }
                    appState.pendingDeepLink = nil
                }
            }
        }
    }

    // MARK: - 월 헤더
    /// "2025년 5월" 라벨 + 가벼운 라인. 카드를 떨어트려 그룹 경계를 시각화.
    private func monthHeader(_ label: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 1)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: - 타임라인 행 분기
    @ViewBuilder
    private func entryRow(_ entry: HistoryEntry) -> some View {
        switch entry {
        case .meeting(let meeting): meetingRow(meeting)
        case .note(let note): noteRow(note)
        }
    }

    // MARK: - 한 겹(노트) 행
    /// 모임 행과 같은 날짜 컬럼 구조를 쓰되, "한 겹" 뱃지·secondary 톤으로 시각 구분.
    /// 탭하면 수정, 롱프레스 컨텍스트 메뉴로 삭제.
    @ViewBuilder
    private func noteRow(_ note: Note) -> some View {
        Button {
            Haptic.light()
            noteToEdit = note
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 2) {
                    Text(dayText(note.date))
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(weekdayText(note.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.caption2)
                            Text("한 겹")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(AppColors.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppColors.secondarySubtle))

                        Spacer()
                    }

                    Text(note.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let photoURL = note.photoURL {
                        CachedAsyncImage(url: URL(string: photoURL))
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    HStack(spacing: 6) {
                        AvatarView(name: note.authorName, size: 20, imageURL: authorImageURL(note.authorId))
                        Text(note.authorName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Haptic.light()
                noteToEdit = note
            } label: {
                Label("수정", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Haptic.medium()
                Task { try? await appState.deleteNote(note.id) }
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    /// 노트 작성자의 프로필 이미지 — 현재 멤버 목록에서 찾음(탈퇴했으면 nil → 이니셜 아바타).
    private func authorImageURL(_ authorId: String) -> String? {
        appState.members.first(where: { $0.id == authorId })?.profileImageURL
    }

    // MARK: - 모임 행
    /// 행 전체(빈 공간 포함)가 탭 가능하도록 contentShape 명시.
    /// .card() 내부의 padding 영역까지 히트 테스트가 닿게 만든다.
    @ViewBuilder
    private func meetingRow(_ meeting: Meeting) -> some View {
        Button {
            Haptic.light()
            selectedMeeting = meeting
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // 날짜 컬럼 — 월은 섹션 헤더가 보여주므로 일(day)만 남기고 요일을 보조로
                VStack(spacing: 2) {
                    Text(dayText(meeting.meetingDate))
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(weekdayText(meeting.meetingDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44)

                // 모임 카드
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(meeting.displayPlace)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Spacer()

                        BadgeView(
                            text: displayStatus(for: meeting).text,
                            color: displayStatus(for: meeting).color
                        )
                    }

                    if let activity = meeting.activity {
                        Text(activity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 주최자 + 참여자: 아바타 stack + 라벨
                    participantsLine(for: meeting)

                    HStack(spacing: 8) {
                        Spacer()
                        if appState.myRecordedMeetingIds.contains(meeting.id) {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                Text("기록 완료")
                                    .font(.caption2)
                            }
                            .foregroundStyle(AppColors.secondary)
                        } else if meeting.meetingDate <= Date() {
                            HStack(spacing: 3) {
                                Image(systemName: "pencil.circle")
                                    .font(.caption2)
                                Text("미기록")
                                    .font(.caption2)
                            }
                            .foregroundStyle(AppColors.warning)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 참여자 라인
    /// "주최자 아바타(테두리 강조) + 참석자 아바타들 + 텍스트 라벨" 형태로 표시.
    /// 출석(attendance) 데이터가 없는 레거시 모임이면 전체 참여자 명단을 보여준다.
    @ViewBuilder
    private func participantsLine(for meeting: Meeting) -> some View {
        let people = participantsForDisplay(meeting: meeting)
        HStack(spacing: 6) {
            HStack(spacing: -4) {
                ForEach(people.prefix(5)) { member in
                    AvatarView(name: member.name, size: 20, imageURL: member.profileImageURL)
                        .overlay(
                            Circle()
                                .stroke(
                                    member.id == meeting.plannerId
                                        ? AppColors.primary
                                        : Color(.systemBackground),
                                    lineWidth: member.id == meeting.plannerId ? 1.5 : 1
                                )
                        )
                }
            }
            Text(participantsLabel(meeting: meeting, people: people))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// 출석 맵에 .going이 한 명이라도 있으면 그 기준, 아니면 명단 전원(레거시 폴백).
    /// 항상 플래너를 맨 앞에 둬서 "주최자가 누구인지" 한눈에 보이게.
    private func participantsForDisplay(meeting: Meeting) -> [Member] {
        let allMemberIds = appState.members.map(\.id)
        let participantIds = Set(meeting.effectiveParticipantIds(allMemberIds: allMemberIds))

        let hasGoing = meeting.attendance.values.contains(.going)
        let filtered: [Member]
        if hasGoing {
            filtered = appState.members.filter {
                participantIds.contains($0.id) && meeting.attendance[$0.id] == .going
            }
        } else {
            filtered = appState.members.filter { participantIds.contains($0.id) }
        }

        if let plannerMember = filtered.first(where: { $0.id == meeting.plannerId }) {
            return [plannerMember] + filtered.filter { $0.id != meeting.plannerId }
        }
        // 플래너가 가족에서 나간 경우: 비정규화된 plannerName만 있고 멤버 객체는 없으므로 그대로 반환.
        return filtered
    }

    private func participantsLabel(meeting: Meeting, people: [Member]) -> String {
        guard !people.isEmpty else { return meeting.plannerName }
        let names = people.map(\.name)
        if names.count <= 3 {
            return names.joined(separator: " · ")
        }
        let head = names.prefix(3).joined(separator: " · ")
        return "\(head) 외 \(names.count - 3)명"
    }

    // MARK: - 통계 hero 카드
    /// 연속 달성 12주 점 그리드 + 누적 모임/평균 별점 sub-pill.
    /// `appState.consecutiveWeeks`는 [project_state]에 계산 로직이 있으니 그대로 사용.
    private var statHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 상단: 큰 연속 달성 표시
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.primary)
                VStack(alignment: .leading, spacing: 0) {
                    if appState.consecutiveWeeks > 0 {
                        Text("\(appState.consecutiveWeeks)주 연속")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        Text("매주 가족과 함께하고 있어요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("이번 주부터 시작해볼까요?")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        Text("매주 모임으로 연속 달성을 쌓아요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // 12주 점 그리드 — 가장 오래된 주 → 이번 주 순서로 12개
            streakDotGrid

            // sub-pill 두 개
            HStack(spacing: 10) {
                subPill(icon: "calendar", text: "총 \(meetings.count)회 모임", tint: AppColors.info)
                subPill(
                    icon: "star.fill",
                    text: appState.averageRating > 0
                        ? "평균 \(String(format: "%.1f", appState.averageRating))점"
                        : "별점 없음",
                    tint: AppColors.warning
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(highlighted: true)
    }

    /// 최근 12주 달성 여부 점 그리드. 왼쪽이 12주 전, 오른쪽이 이번 주.
    /// 한 주에 .cancelled 아닌 모임이 1개라도 있고 그 날짜가 그 주에 속하면 채워진 점.
    private var streakDotGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<12, id: \.self) { offset in
                    Circle()
                        .fill(weekHasMeeting(weeksAgo: 11 - offset)
                              ? AppColors.primary
                              : AppColors.primarySubtle)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(AppColors.primary.opacity(weekHasMeeting(weeksAgo: 11 - offset) ? 0 : 0.25),
                                        lineWidth: 1)
                        )
                }
                Spacer(minLength: 0)
            }

            // 범위 라벨 — 사용자가 가리키는 게 뭔지 한눈에 알게
            HStack(spacing: 0) {
                Text("12주 전")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("→")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("이번 주")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            // 점 그리드 좌우 끝과 맞추기 — 12개 × 14pt + 11개 × 6pt(spacing) = 234pt
            .frame(width: 12 * 14 + 11 * 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func subPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    /// `weeksAgo`주 전이 "채워진" 주인지 — 모임 또는 한 겹(노트)이 하나라도 있으면 채움. ISO 8601 월~일 기준.
    private func weekHasMeeting(weeksAgo: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let now = Date()
        guard let targetWeek = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now) else {
            return false
        }
        let key = weekKey(for: targetWeek, calendar: calendar)
        let hasMeeting = meetings.contains { meeting in
            meeting.status != .cancelled
                && meeting.meetingDate <= now
                && weekKey(for: meeting.meetingDate, calendar: calendar) == key
        }
        let hasNote = notes.contains { note in
            note.date <= now
                && weekKey(for: note.date, calendar: calendar) == key
        }
        return hasMeeting || hasNote
    }

    private func weekKey(for date: Date, calendar: Calendar) -> Int {
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return year * 100 + week
    }

    // MARK: - Helpers
    private func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    /// 일자 아래에 작게 보이는 요일 라벨. 월은 섹션 헤더가 보여줘서 여기선 요일이 더 유용.
    private func weekdayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func displayStatus(for meeting: Meeting) -> (text: String, color: Color) {
        if meeting.status == .cancelled {
            return ("취소", Color(.systemGray4))
        }
        if meeting.meetingDate <= Date() {
            return ("완료", Color.gray)
        }
        switch meeting.status {
        case .planning: return ("계획 중", AppColors.info)
        case .confirmed: return ("확정", AppColors.secondary)
        case .completed: return ("완료", Color.gray)
        case .cancelled: return ("취소", Color(.systemGray4))
        }
    }
}

#Preview("히스토리 목록") {
    HistoryView()
}
