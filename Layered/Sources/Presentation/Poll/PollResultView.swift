import SwiftUI

struct PollResultView: View {
    let initialPoll: Poll
    let onBack: () -> Void
    var meetingId: String = ""

    @Environment(AppState.self) private var appState: AppState
    @State private var poll: Poll
    /// 0(빈 바) → 1(실제값)로 spring으로 차오르는 reveal 진행도. .task로 한 번만 트리거.
    @State private var revealProgress: CGFloat = 0
    @State private var revealedOptionIds: Set<String> = []

    init(poll: Poll, onBack: @escaping () -> Void, meetingId: String = "") {
        self.initialPoll = poll
        self.onBack = onBack
        self.meetingId = meetingId
        _poll = State(initialValue: poll)
    }

    private var totalVotes: Int {
        poll.options.reduce(0) { $0 + $1.voteCount }
    }

    private var maxVotes: Int {
        poll.options.map(\.voteCount).max() ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "투표 결과",
                backAction: onBack
            )

            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - 질문
                    Text(poll.question)
                        .font(.title3)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // MARK: - 확정 뱃지 + 참여 수
                    HStack(spacing: 10) {
                        BadgeView(text: "확정", color: AppColors.secondary)

                        Text("\(totalVotes)명 참여")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    // MARK: - 결과 바 그래프
                    ForEach(Array(poll.options.enumerated()), id: \.element.id) { index, option in
                        let isWinner = option.voteCount == maxVotes && maxVotes > 0
                        let isRevealed = revealedOptionIds.contains(option.id)
                        let fullWidthFraction: CGFloat = totalVotes > 0
                            ? CGFloat(option.voteCount) / CGFloat(totalVotes)
                            : 0
                        let animatedFraction = fullWidthFraction * revealProgress
                        let animatedCount = Int((Double(option.voteCount) * Double(revealProgress)).rounded())

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(option.title)
                                    .font(.subheadline)
                                    .fontWeight(isWinner ? .bold : .regular)

                                Spacer()

                                Text("\(animatedCount)표")
                                    .font(.subheadline)
                                    .fontWeight(isWinner ? .bold : .regular)
                                    .foregroundStyle(isWinner ? .primary : .secondary)
                                    .contentTransition(.numericText())
                            }

                            // Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(.systemGray5))
                                        .frame(height: 10)

                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isWinner ? AppColors.primary : Color(.systemGray3))
                                        .frame(
                                            width: geo.size.width * animatedFraction,
                                            height: 10
                                        )
                                }
                            }
                            .frame(height: 10)

                            // 공개 투표: 투표자 표시
                            if !poll.isAnonymous && !option.voterIds.isEmpty {
                                Text(voterNames(for: option.voterIds))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .card(highlighted: isWinner)
                        .scaleEffect(isWinner && isRevealed ? 1.02 : 1.0)
                        .shadow(
                            color: isWinner && isRevealed ? AppColors.primary.opacity(0.25) : .clear,
                            radius: isWinner && isRevealed ? 12 : 0,
                            y: 4
                        )
                        .opacity(isRevealed ? 1 : 0)
                        .offset(y: isRevealed ? 0 : 12)
                        .animation(.spring(duration: 0.5, bounce: 0.3), value: isRevealed)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .task {
            guard !meetingId.isEmpty else { return }
            if let updated = try? await appState.getPoll(meetingId: meetingId, pollId: poll.id) {
                poll = updated
            }
        }
        .onAppear { runReveal() }
        .swipeBack(onBack: onBack)
    }

    /// 옵션 카드 등장은 80ms 간격 stagger, 1등은 한 번 더 늦게.
    /// 바 width와 표 수는 revealProgress가 0→1로 spring으로 차오르며 같이 따라감.
    private func runReveal() {
        revealedOptionIds.removeAll()
        revealProgress = 0
        let winnerId = poll.options.first(where: { $0.voteCount == maxVotes && maxVotes > 0 })?.id
        for (index, option) in poll.options.enumerated() {
            let baseDelay = 0.08 * Double(index)
            let extra = (option.id == winnerId) ? 0.18 : 0.0
            let optionId = option.id
            DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + extra) {
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                    _ = revealedOptionIds.insert(optionId)
                }
            }
        }
        // 카드들이 다 등장한 직후 막대가 0→실제값으로 차오름
        let totalDelay = 0.08 * Double(poll.options.count) + 0.18
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            withAnimation(.spring(duration: 0.8, bounce: 0.2)) {
                revealProgress = 1
            }
        }
    }

    private func voterNames(for ids: [String]) -> String {
        let members = appState.members
        return ids.map { id in
            members.first(where: { $0.id == id })?.name ?? id
        }.joined(separator: ", ")
    }
}

#Preview("투표 결과") {
    PollResultPreviewHost()
}

/// 프리뷰에서 reveal 모션을 반복 확인할 수 있게 "다시 재생" 버튼을 단 래퍼.
/// `id`를 바꿔주면 PollResultView가 새로 마운트되어 .onAppear가 다시 발화.
private struct PollResultPreviewHost: View {
    @State private var replayKey = UUID()

    var body: some View {
        VStack(spacing: 0) {
            PollResultView(poll: MockData.poll, onBack: {})
                .id(replayKey)
                .environment(AppState())

            Button {
                replayKey = UUID()
            } label: {
                Text("↻ 다시 재생")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.primarySubtle)
                    .clipShape(Capsule())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .buttonStyle(.plain)
        }
    }
}
