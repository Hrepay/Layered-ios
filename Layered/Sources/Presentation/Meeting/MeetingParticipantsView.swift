import SwiftUI

struct MeetingParticipantsView: View {
    @Binding var meeting: Meeting
    let onBack: () -> Void

    @Environment(AppState.self) private var appState: AppState

    @State private var expandedMember: Member?
    @State private var showAddSheet = false
    @State private var actionTarget: Member?
    @State private var toast: String?
    @State private var nudgedIds: Set<String> = []
    @State private var busy = false

    private var allMemberIds: [String] { appState.members.map(\.id) }
    private var participantIds: [String] {
        meeting.effectiveParticipantIds(allMemberIds: allMemberIds)
    }
    private var participants: [Member] {
        appState.members.filter { participantIds.contains($0.id) }
    }
    private var nonParticipants: [Member] {
        appState.members.filter { !participantIds.contains($0.id) }
    }
    private var myId: String? { appState.currentUser?.id }

    private func status(_ member: Member) -> Meeting.AttendanceStatus? {
        meeting.attendanceStatus(for: member.id)
    }

    /// 불참을 제외한 "실제 참여 명단"(확정 + 미정).
    private var mainParticipants: [Member] {
        participants.filter { status($0) != .notGoing }
    }
    private var declinedParticipants: [Member] {
        participants.filter { status($0) == .notGoing }
    }

    private var goingCount: Int {
        participants.filter { status($0) == .going }.count
    }
    private var notGoingCount: Int {
        participants.filter { status($0) == .notGoing }.count
    }
    private var pendingCount: Int {
        participants.count - goingCount - notGoingCount
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "참여 인원 (\(mainParticipants.count)명)",
                backAction: onBack,
                trailingMenu: AnyView(
                    Button {
                        Haptic.light()
                        showAddSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    .disabled(nonParticipants.isEmpty)
                )
            )

            if participants.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        summaryRow
                            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                            .listRowSeparator(.hidden)
                    }

                    Section {
                        ForEach(mainParticipants) { member in
                            participantListRow(member)
                        }
                    }

                    if !declinedParticipants.isEmpty {
                        Section {
                            ForEach(declinedParticipants) { member in
                                participantListRow(member)
                                    .opacity(0.55)
                            }
                        } header: {
                            Text("불참 \(declinedParticipants.count)명")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .disabled(busy)
            }
        }
        .swipeBack(onBack: onBack)
        .sheet(isPresented: $showAddSheet) {
            addParticipantsSheet
        }
        .confirmationDialog(
            actionTarget?.name ?? "",
            isPresented: Binding(
                get: { actionTarget != nil },
                set: { if !$0 { actionTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: actionTarget
        ) { member in
            Button("참석 확정") {
                Haptic.medium()
                Task { await applyAttendance(member, .going) }
            }
            Button("불참") {
                Haptic.medium()
                Task { await applyAttendance(member, .notGoing) }
            }
            Button("미정") {
                Haptic.light()
                Task { await applyAttendance(member, nil) }
            }
            if nudgedIds.contains(member.id) {
                Button("콕 찌르기 (이미 보냄)") {
                    Haptic.light()
                    showToast("이미 콕 찔렀어요")
                }
            } else {
                Button("콕 찌르기") {
                    Haptic.medium()
                    Task { await nudge(member) }
                }
            }
            Button("취소", role: .cancel) {}
        }
        // 액션시트 버튼 글자색 검정 (디자인 규칙: 컬러 텍스트 금지). 다크모드 대응 위해 .primary.
        .tint(Color.primary)
        .overlay {
            if let member = expandedMember {
                ProfileImageViewer(member: member) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedMember = nil
                    }
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - 요약

    private var summaryRow: some View {
        HStack(spacing: 10) {
            summaryChip(icon: "checkmark.circle.fill", color: AppColors.secondary, label: "확정", count: goingCount)
            summaryChip(icon: "questionmark.circle.fill", color: AppColors.warning, label: "미정", count: pendingCount)
            summaryChip(icon: "xmark.circle.fill", color: Color.red, label: "불참", count: notGoingCount)
        }
    }

    private func summaryChip(icon: String, color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
            Text("\(label) \(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 참여자 행

    @ViewBuilder
    private func participantListRow(_ member: Member) -> some View {
        participantRow(member)
            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await removeParticipant(member) }
                } label: {
                    Label("제외", systemImage: "person.fill.xmark")
                }
            }
    }

    @ViewBuilder
    private func participantRow(_ member: Member) -> some View {
        let isMe = member.id == myId
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                AvatarView(name: member.name, size: 48, imageURL: member.profileImageURL)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptic.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedMember = member
                        }
                    }

                Text(member.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Spacer()

                if !isMe {
                    statusBadge(status(member))
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isMe else { return }
                Haptic.light()
                actionTarget = member
            }

            if isMe {
                myAttendanceControl(member)
            }
        }
    }

    private func statusBadge(_ status: Meeting.AttendanceStatus?) -> some View {
        switch status {
        case .going:
            return BadgeView(text: "참석 확정", color: AppColors.secondary)
        case .notGoing:
            return BadgeView(text: "불참", color: Color.red)
        case nil:
            return BadgeView(text: "미정", color: AppColors.warning)
        }
    }

    // MARK: - 내 참석 토글

    @ViewBuilder
    private func myAttendanceControl(_ member: Member) -> some View {
        let current = status(member)
        HStack(spacing: 10) {
            attendanceButton(
                title: "참석 확정",
                icon: "checkmark.circle.fill",
                isActive: current == .going,
                activeColor: AppColors.secondary
            ) {
                await toggleMyAttendance(to: .going)
            }
            attendanceButton(
                title: "불참",
                icon: "xmark.circle.fill",
                isActive: current == .notGoing,
                activeColor: Color.red
            ) {
                await toggleMyAttendance(to: .notGoing)
            }
        }
    }

    private func attendanceButton(
        title: String,
        icon: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Haptic.medium()
            Task { await action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(isActive ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isActive ? activeColor : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: - 구성원 추가 시트

    private var addParticipantsSheet: some View {
        NavigationStack {
            Group {
                if nonParticipants.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("추가할 수 있는 가족이 없어요")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(nonParticipants) { member in
                            Button {
                                Haptic.light()
                                Task { await addParticipant(member) }
                            } label: {
                                HStack(spacing: 14) {
                                    AvatarView(name: member.name, size: 44, imageURL: member.profileImageURL)
                                    Text(member.name)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(AppColors.primary)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("구성원 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { showAddSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("참여 중인 인원이 없어요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func syncFromAppState() {
        if let updated = appState.meetings.first(where: { $0.id == meeting.id }) {
            meeting = updated
        }
    }

    private func toggleMyAttendance(to target: Meeting.AttendanceStatus) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        // 같은 상태를 다시 누르면 미정으로 되돌림.
        let next: Meeting.AttendanceStatus? =
            meeting.attendance[myId ?? ""] == target ? nil : target
        do {
            try await appState.setMyAttendance(meetingId: meeting.id, status: next)
            syncFromAppState()
        } catch {
            showToast(AppError.from(error).message)
        }
    }

    private func applyAttendance(_ member: Member, _ status: Meeting.AttendanceStatus?) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await appState.setAttendance(meetingId: meeting.id, memberId: member.id, status: status)
            syncFromAppState()
        } catch {
            showToast(AppError.from(error).message)
        }
    }

    private func nudge(_ member: Member) async {
        guard !busy else { return }
        // 이번 화면 세션에서 이미 찌른 사람이면 재발송 없이 안내만.
        guard !nudgedIds.contains(member.id) else {
            showToast("이미 콕 찔렀어요")
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await appState.sendNudge(meetingId: meeting.id, targetUserId: member.id)
            nudgedIds.insert(member.id)
            showToast("\(member.name)님을 콕 찔렀어요")
        } catch {
            showToast(AppError.from(error).message)
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text {
                withAnimation { toast = nil }
            }
        }
    }

    private func addParticipant(_ member: Member) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        var ids = participantIds
        guard !ids.contains(member.id) else { return }
        ids.append(member.id)
        do {
            try await appState.setMeetingParticipants(meetingId: meeting.id, participantIds: ids)
            syncFromAppState()
        } catch {
            showToast(AppError.from(error).message)
        }
    }

    private func removeParticipant(_ member: Member) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let ids = participantIds.filter { $0 != member.id }
        do {
            try await appState.setMeetingParticipants(meetingId: meeting.id, participantIds: ids)
            syncFromAppState()
        } catch {
            showToast(AppError.from(error).message)
        }
    }
}

private struct ProfileImageViewer: View {
    let member: Member
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptic.light()
                    onDismiss()
                }

            VStack(spacing: 18) {
                AvatarView(
                    name: member.name,
                    size: 240,
                    imageURL: member.profileImageURL
                )
                .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 6)

                Text(member.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .padding(40)
        }
    }
}
