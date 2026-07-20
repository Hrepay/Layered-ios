import SwiftUI

struct PollVoteView: View {
    let initialPoll: Poll
    let onBack: () -> Void
    var meetingId: String = ""

    @Environment(AppState.self) private var appState: AppState

    @State private var poll: Poll
    @State private var selectedOptions: Set<String> = []
    @State private var previousVotes: Set<String> = []
    @State private var hasVoted = false
    @State private var showDeleteAlert = false
    @State private var toast: ToastData?

    init(poll: Poll, onBack: @escaping () -> Void, meetingId: String = "") {
        self.initialPoll = poll
        self.onBack = onBack
        self.meetingId = meetingId
        _poll = State(initialValue: poll)
    }

    private var totalVotes: Int {
        poll.options.map(\.voteCount).max() == 0 ? 0 : poll.options.reduce(0) { $0 + $1.voteCount }
    }

    private var maxVotes: Int {
        poll.options.map(\.voteCount).max() ?? 0
    }

    private var uniqueVoterCount: Int {
        var allVoterIds = Set<String>()
        for option in poll.options {
            for voterId in option.voterIds {
                allVoterIds.insert(voterId)
            }
        }
        return allVoterIds.count
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "투표",
                backAction: onBack,
                trailingMenu: AnyView(
                    Menu {
                        Button("투표 삭제", systemImage: "trash.fill", role: .destructive) {
                            showDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                )
            )

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - 질문
                    Text(poll.question)
                        .font(.title3)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // MARK: - 익명 뱃지 + 참여 수
                    HStack(spacing: 10) {
                        if poll.isAnonymous {
                            BadgeView(text: "익명 투표", color: AppColors.info)
                        }

                        Spacer()

                        if hasVoted {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.caption)
                                Text("\(uniqueVoterCount)명 참여")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    // MARK: - 선택지 + 결과 통합
                    ForEach(poll.options) { option in
                        let isSelected = selectedOptions.contains(option.id)
                        let isWinner = hasVoted && option.voteCount == maxVotes && maxVotes > 0

                        Button {
                            Haptic.light()
                            withAnimation(.spring(duration: 0.2)) {
                                if isSelected {
                                    selectedOptions.remove(option.id)
                                } else {
                                    if !poll.allowMultiple {
                                        selectedOptions.removeAll()
                                    }
                                    selectedOptions.insert(option.id)
                                }
                            }
                        } label: {
                            VStack(spacing: 10) {
                                HStack(spacing: 14) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isSelected ? AppColors.primary : Color(.systemGray3))
                                        .animation(.spring(duration: 0.2), value: isSelected)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.title)
                                            .font(.subheadline)
                                            .fontWeight(isWinner ? .bold : .medium)
                                            .foregroundStyle(.primary)

                                        if let desc = option.description {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        if let urlString = option.linkURL,
                                           let url = URL(string: urlString) {
                                            Link(destination: url) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "link")
                                                        .font(.caption2)
                                                        .foregroundStyle(AppColors.primary)
                                                    Text(url.host ?? urlString)
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                        .foregroundStyle(.primary)
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(
                                                    Capsule()
                                                        .fill(AppColors.primarySubtle)
                                                )
                                            }
                                            .padding(.top, 2)
                                        }
                                    }

                                    Spacer()

                                    if hasVoted {
                                        Text("\(option.voteCount)표")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(isWinner ? AppColors.primary : .secondary)
                                    }
                                }

                                // MARK: - 바 그래프 (투표 후)
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
                                                .animation(.spring(duration: 0.4), value: option.voteCount)
                                        }
                                    }
                                    .frame(height: 6)

                                    // 공개 투표: 투표자 닉네임 표시
                                    if !poll.isAnonymous && !option.voterIds.isEmpty {
                                        Text(voterNames(for: option.voterIds))
                                            .font(.caption2)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(isSelected ? AppColors.primarySubtle : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(isSelected ? AppColors.primary : .clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }

            // MARK: - 투표 버튼
            Button {
                Haptic.medium()
                if !meetingId.isEmpty {
                    Task {
                        do {
                            let toRemove = previousVotes.subtracting(selectedOptions)
                            for optionId in toRemove {
                                try await appState.removeVote(meetingId: meetingId, pollId: poll.id, optionId: optionId)
                            }
                            let toAdd = selectedOptions.subtracting(previousVotes)
                            for optionId in toAdd {
                                try await appState.vote(meetingId: meetingId, pollId: poll.id, optionId: optionId)
                            }
                            if let updated = try? await appState.getPoll(meetingId: meetingId, pollId: poll.id) {
                                withAnimation { poll = updated }
                            }
                            previousVotes = selectedOptions
                            let wasVoted = hasVoted
                            withAnimation { hasVoted = true }
                            toast = ToastData(type: .success, message: wasVoted ? "투표가 변경되었습니다" : "투표 완료!")
                        } catch {
                            appState.error = AppError.from(error)
                        }
                    }
                } else {
                    withAnimation { hasVoted = true }
                }
            } label: {
                Text(hasVoted ? "투표 변경" : "투표하기")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(selectedOptions.isEmpty ? Color(.systemGray4) : AppColors.primary)
                    )
            }
            .disabled(selectedOptions.isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .toast($toast)
        .alert("투표 삭제", isPresented: $showDeleteAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                if !meetingId.isEmpty {
                    Task {
                        do {
                            try await appState.deletePoll(meetingId: meetingId, pollId: poll.id)
                            onBack()
                        } catch {
                            appState.error = AppError.from(error)
                        }
                    }
                } else {
                    onBack()
                }
            }
        } message: {
            Text("이 투표를 삭제하시겠습니까?\n삭제하면 되돌릴 수 없어요.")
        }
        .onAppear {
            guard let userId = appState.currentUser?.id else { return }
            let voted = Set(poll.options.filter { $0.voterIds.contains(userId) }.map(\.id))
            if !voted.isEmpty {
                selectedOptions = voted
                previousVotes = voted
                hasVoted = true
            }
        }
        .swipeBack(onBack: onBack)
    }

    private func voterNames(for ids: [String]) -> String {
        let members = appState.members
        return ids.map { id in
            members.first(where: { $0.id == id })?.name ?? "Guest"
        }.joined(separator: ", ")
    }
}

#Preview("진행 중인 투표") {
    PollVoteView(poll: MockData.poll, onBack: {})
}
