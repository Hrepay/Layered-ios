import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState: AppState
    @State private var selectedMeeting: Meeting?

    private var meetings: [Meeting] { appState.meetings }

    var body: some View {
        NavigationStack {
            Group {
                if meetings.isEmpty {
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
                            }
                            .padding(.top, 12)

                            // MARK: - 상단 통계 카드
                            HStack(spacing: 12) {
                                statCard(
                                    icon: "person.3.fill",
                                    value: "\(meetings.count)",
                                    label: "총 모임"
                                )
                                statCard(
                                    icon: "star.fill",
                                    value: (appState.averageRating) > 0
                                        ? String(format: "%.1f", appState.averageRating)
                                        : "-",
                                    label: "평균 별점"
                                )
                                statCard(
                                    icon: "flame.fill",
                                    value: (appState.consecutiveWeeks) > 0
                                        ? "\(appState.consecutiveWeeks)주"
                                        : "-",
                                    label: "연속 달성"
                                )
                            }
                            .padding(.top, 4)

                            // MARK: - 타임라인
                            ForEach(meetings) { meeting in
                                Button {
                                    Haptic.light()
                                    selectedMeeting = meeting
                                } label: {
                                    HStack(alignment: .top, spacing: 14) {
                                        // 날짜 컬럼
                                        VStack(spacing: 2) {
                                            Text(dayText(meeting.meetingDate))
                                                .font(.title3)
                                                .fontWeight(.bold)

                                            Text(monthText(meeting.meetingDate))
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

                                            HStack(spacing: 8) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "person.fill")
                                                        .font(.caption2)
                                                    Text(meeting.plannerName)
                                                        .font(.caption2)
                                                }
                                                .foregroundStyle(.secondary)

                                                Spacer()

                                                if appState.myRecordedMeetingIds.contains(meeting.id) == true {
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
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .refreshable {
                        await appState.refreshMeetings()
                        await appState.checkMyRecords()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Stat Card
    private func statCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppColors.primary)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.primary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(AppColors.primarySubtle)
        )
    }

    // MARK: - Helpers
    private func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func monthText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월"
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
