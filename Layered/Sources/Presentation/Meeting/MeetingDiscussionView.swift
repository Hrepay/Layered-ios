import SwiftUI

/// 투표(있을 경우)와 의견을 한 화면에서 처리하는 push 네비게이션 뷰.
/// 시트 중첩 이슈를 피하고 채팅-스타일의 인라인 입력 바로 등록.
struct MeetingDiscussionView: View {
    let meeting: Meeting
    let onBack: () -> Void

    @Environment(AppState.self) private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var poll: Poll?
    @State private var comments: [MeetingComment] = []
    @State private var selectedOptions: Set<String> = []
    @State private var hasVoted = false
    @State private var votingOptionId: String?
    @State private var inputText = ""
    @State private var isSubmittingComment = false
    @State private var commentToDelete: MeetingComment?
    @State private var commentToEdit: MeetingComment?
    @State private var visibleCommentCount: Int = 10
    @State private var pollOnScreen: Bool = true
    @FocusState private var inputFocused: Bool

    private static let initialCommentPageSize = 10
    private static let commentPageStep = 5

    private var shouldShowPollJumpButton: Bool {
        poll != nil && !pollOnScreen
    }

    private var hasPoll: Bool {
        meeting.hasPoll && poll != nil
    }

    private var title: String {
        hasPoll ? "투표 & 의견" : "의견"
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                NavBar(title: title, backAction: onBack)

                List {
                    if let poll {
                        pollSection(poll: poll)
                            .id("poll_top")
                            .onAppear { pollOnScreen = true }
                            .onDisappear { pollOnScreen = false }
                            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 8, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    commentsHeader
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 4, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if comments.isEmpty {
                        emptyCommentsView
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        let hiddenCount = max(0, comments.count - visibleCommentCount)
                        if hiddenCount > 0 {
                            loadMoreButton(hiddenCount: hiddenCount)
                                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        ForEach(Array(comments.suffix(visibleCommentCount))) { comment in
                            commentRow(comment)
                                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    commentSwipeActions(for: comment)
                                }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("comments_bottom")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: comments.count) { _, newCount in
                    if visibleCommentCount > newCount {
                        visibleCommentCount = max(Self.initialCommentPageSize, newCount)
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("comments_bottom", anchor: .bottom)
                    }
                }
                .overlay(alignment: .top) {
                    if shouldShowPollJumpButton {
                        pollJumpButton(proxy: proxy)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: shouldShowPollJumpButton)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: meeting.id) {
            await reload()
        }
        .task(id: meeting.id) {
            await observeComments()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await reload() } }
        }
        .refreshable {
            await reload()
        }
        .alert("의견 삭제", isPresented: Binding(
            get: { commentToDelete != nil },
            set: { if !$0 { commentToDelete = nil } }
        ), presenting: commentToDelete) { comment in
            Button("취소", role: .cancel) { commentToDelete = nil }
            Button("삭제", role: .destructive) {
                Task { await deleteComment(comment) }
            }
        } message: { _ in
            Text("이 의견을 삭제하시겠습니까?")
        }
        .sheet(item: $commentToEdit) { comment in
            EditCommentSheet(
                original: comment,
                isBusy: $isSubmittingComment,
                onSave: { newText in
                    await submitEditComment(comment: comment, newText: newText)
                },
                onCancel: { commentToEdit = nil }
            )
        }
        .swipeBack(onBack: onBack)
    }

    // MARK: - Poll section

    @ViewBuilder
    private func pollSection(poll: Poll) -> some View {
        let maxVotes = poll.options.map(\.voteCount).max() ?? 0
        let totalVotes = poll.options.reduce(0) { $0 + $1.voteCount }

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(AppColors.primary)
                Text(poll.question.isEmpty ? "어디로 갈까요?" : poll.question)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }

            Text("탭해서 바로 투표, 다시 탭하면 취소돼요")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(poll.options) { option in
                optionRow(option: option, maxVotes: maxVotes, totalVotes: totalVotes)
            }
        }
        .card()
    }

    @ViewBuilder
    private func optionRow(option: PollOption, maxVotes: Int, totalVotes: Int) -> some View {
        let isSelected = selectedOptions.contains(option.id)
        let isWinner = hasVoted && option.voteCount == maxVotes && maxVotes > 0
        let isBusy = votingOptionId == option.id

        Button {
            Haptic.light()
            Task { await toggleVote(optionId: option.id) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // 상단: 제목 + (오른쪽 끝) 링크
                HStack(spacing: 8) {
                    Text(option.title)
                        .font(.body)
                        .fontWeight(isWinner ? .bold : .medium)
                        .foregroundStyle(.primary)
                    Spacer()
                    if let urlString = option.linkURL,
                       let url = URL(string: urlString) {
                        Link(destination: url) {
                            Image(systemName: "link")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColors.primary)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(AppColors.primarySubtle))
                        }
                    }
                }

                // 하단: 바 + 표수 (투표 후) 또는 진행 스피너
                HStack(spacing: 10) {
                    if hasVoted {
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
                            }
                        }
                        .frame(height: 6)

                        Text("\(option.voteCount)표")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(isWinner ? AppColors.primary : .secondary)
                    } else if isBusy {
                        Spacer()
                        ProgressView().scaleEffect(0.7)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? AppColors.primarySubtle : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? AppColors.primary : Color(.systemGray5), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(votingOptionId != nil)
    }

    // MARK: - Comments section

    @ViewBuilder
    private var commentsHeader: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 1)
            Text(comments.isEmpty ? "의견" : "의견 \(comments.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emptyCommentsView: some View {
        Text("아직 의견이 없어요.\n아래에서 첫 의견을 남겨보세요!")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
    }

    @ViewBuilder
    private func commentSwipeActions(for comment: MeetingComment) -> some View {
        if comment.userId == appState.currentUser?.id {
            Button(role: .destructive) {
                Haptic.light()
                commentToDelete = comment
            } label: {
                Label("삭제", systemImage: "trash")
            }

            Button {
                Haptic.light()
                commentToEdit = comment
            } label: {
                Label("수정", systemImage: "pencil")
            }
            .tint(AppColors.primary)
        }
    }

    @ViewBuilder
    private func loadMoreButton(hiddenCount: Int) -> some View {
        Button {
            Haptic.light()
            withAnimation(.easeOut(duration: 0.2)) {
                visibleCommentCount = min(comments.count, visibleCommentCount + Self.commentPageStep)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("이전 의견 \(hiddenCount)개 더 보기")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func commentRow(_ comment: MeetingComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(name: comment.userName, size: 36, imageURL: memberImageURL(for: comment.userId))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.userName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(formatRelativeTime(comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(comment.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Input bar

    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if inputText.isEmpty {
                    Text("의견을 남겨주세요 (200자)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                }
                TextField("", text: $inputText, axis: .vertical)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .focused($inputFocused)
                    .lineLimit(1...4)
                    .onChange(of: inputText) { _, newValue in
                        if newValue.count > 200 {
                            inputText = String(newValue.prefix(200))
                        }
                    }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Button {
                Haptic.medium()
                Task { await submitComment() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(canSubmit ? AppColors.primary : Color(.systemGray4))
                    .clipShape(Circle())
            }
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            Color(.systemBackground)
                .overlay(alignment: .top) { Divider() }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmittingComment
    }

    // MARK: - Actions

    @MainActor
    private func reload() async {
        if meeting.hasPoll {
            let polls = try? await appState.getPolls(meetingId: meeting.id)
            poll = polls?.first
            syncSelectedFromPoll()
        } else {
            poll = nil
        }
        // 의견은 observeMeetingComments 스트림이 실시간으로 반영하므로 여기선 로드하지 않음.
    }

    @MainActor
    private func observeComments() async {
        for await latest in appState.observeMeetingComments(meetingId: meeting.id) {
            comments = latest
        }
    }

    private func syncSelectedFromPoll() {
        guard let userId = appState.currentUser?.id, let poll else { return }
        let voted = Set(poll.options.filter { $0.voterIds.contains(userId) }.map(\.id))
        selectedOptions = voted
        hasVoted = !voted.isEmpty
    }

    @MainActor
    private func toggleVote(optionId: String) async {
        guard let pollId = poll?.id, votingOptionId == nil else { return }
        let wasSelected = selectedOptions.contains(optionId)
        votingOptionId = optionId
        defer { votingOptionId = nil }
        do {
            if wasSelected {
                try await appState.removeVote(meetingId: meeting.id, pollId: pollId, optionId: optionId)
            } else {
                try await appState.vote(meetingId: meeting.id, pollId: pollId, optionId: optionId)
            }
            // 서버에서 최신 결과 받아와서 selectedOptions/voteCount 갱신
            if let updated = try? await appState.getPoll(meetingId: meeting.id, pollId: pollId) {
                withAnimation { poll = updated }
                syncSelectedFromPoll()
            }
        } catch {
            appState.error = AppError.from(error)
        }
    }

    @MainActor
    private func submitComment() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSubmittingComment = true
        defer { isSubmittingComment = false }
        do {
            _ = try await appState.addMeetingComment(meetingId: meeting.id, text: text)
            inputText = ""
            inputFocused = false
            // listener가 곧 새 의견을 포함한 목록을 push → 자동 하단 스크롤도 트리거됨.
        } catch {
            appState.error = AppError.from(error)
        }
    }

    @MainActor
    private func submitEditComment(comment: MeetingComment, newText: String) async {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != comment.text else { return }
        isSubmittingComment = true
        defer { isSubmittingComment = false }
        do {
            try await appState.updateMeetingComment(meetingId: meeting.id, commentId: comment.id, text: text)
            commentToEdit = nil
        } catch {
            appState.error = AppError.from(error)
        }
    }

    @MainActor
    private func deleteComment(_ comment: MeetingComment) async {
        isSubmittingComment = true
        defer { isSubmittingComment = false }
        do {
            try await appState.deleteMeetingComment(meetingId: meeting.id, commentId: comment.id)
            commentToDelete = nil
        } catch {
            appState.error = AppError.from(error)
        }
    }

    // MARK: - Poll jump floating button

    @ViewBuilder
    private func pollJumpButton(proxy: ScrollViewProxy) -> some View {
        Button {
            Haptic.light()
            withAnimation(.easeOut(duration: 0.35)) {
                proxy.scrollTo("poll_top", anchor: .top)
            }
        } label: {
            Text("투표 하기")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(AppColors.primarySubtle))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func memberImageURL(for userId: String) -> String? {
        appState.members.first(where: { $0.id == userId })?.profileImageURL
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        MeetingDiscussionView(meeting: MockData.meetings[0], onBack: {})
    }
}

// MARK: - 의견 수정 시트 (내부 State로 comment.text 초기화)

private struct EditCommentSheet: View {
    let original: MeetingComment
    @Binding var isBusy: Bool
    let onSave: (String) async -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(original: MeetingComment, isBusy: Binding<Bool>, onSave: @escaping (String) async -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        self._isBusy = isBusy
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: original.text)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("의견 수정")
                    .font(.title3)
                    .fontWeight(.bold)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("의견을 남겨주세요")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                    }
                    TextEditor(text: $text)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onChange(of: text) { _, newValue in
                    if newValue.count > 200 {
                        text = String(newValue.prefix(200))
                    }
                }

                HStack {
                    Spacer()
                    Text("\(text.count)/200")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let snapshot = text
                        Task { await onSave(snapshot) }
                    }
                    .disabled(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        text == original.text ||
                        isBusy
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
