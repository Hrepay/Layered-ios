import SwiftUI
import LinkPresentation

struct EditMeetingView: View {
    let meeting: Meeting
    let onBack: () -> Void
    let onSaved: (Meeting) -> Void

    @Environment(AppState.self) private var appState: AppState

    @State private var date: Date
    // 단일 장소 모드
    @State private var place: String
    @State private var placeURL: String
    // 후보 모드
    @State private var useCandidates: Bool
    @State private var candidates: [PlaceCandidateDraft] = []
    @State private var initialPollId: String?
    @State private var isLoadingPoll: Bool

    @State private var activity: String
    @State private var selectedPresets: Set<ActivityPreset> = []
    @State private var linkMetadata: LPLinkMetadata?
    @State private var isLoadingLink = false
    @State private var showPastDateAlert = false
    @State private var showReactivateAlert = false
    @State private var isSaving = false

    private var finalActivity: String? {
        let presetLabels = selectedPresets.map(\.label)
        let combined = activity.isEmpty ? presetLabels : presetLabels + [activity]
        return combined.isEmpty ? nil : combined.joined(separator: ", ")
    }

    private var validCandidateOptions: [PollOption] {
        PlaceCandidateDraft.toPollOptions(candidates)
    }

    /// 저장 시 cancelled/completed 모임이 미래 시점으로 옮겨져 자동으로 다시 활성화되는지.
    /// EditMeetingView가 trailing 액션 분기와 alert 메시지에서 모두 참조.
    private var willReactivate: Bool {
        date > Date()
            && (meeting.status == .completed || meeting.status == .cancelled)
    }

    private var reactivateAlertMessage: String {
        let from = meeting.status == .completed ? "완료된" : "취소된"
        return "이 모임은 \(from) 모임이에요.\n저장하면 다시 다가오는 모임으로 홈에 표시됩니다."
    }

    private var canSave: Bool {
        if isSaving { return false }
        if useCandidates {
            // 후보 모드면 Poll 로드 후 + 유효 후보 2개 이상
            return !isLoadingPoll && validCandidateOptions.count >= 2
        }
        return !place.isEmpty
    }

    init(meeting: Meeting, onBack: @escaping () -> Void, onSaved: @escaping (Meeting) -> Void) {
        self.meeting = meeting
        self.onBack = onBack
        self.onSaved = onSaved
        _date = State(initialValue: meeting.meetingDate)
        _place = State(initialValue: meeting.place)
        _placeURL = State(initialValue: meeting.placeURL ?? "")
        _useCandidates = State(initialValue: meeting.hasPoll)
        _isLoadingPoll = State(initialValue: meeting.hasPoll)
        // 기존 활동에서 프리셋 매칭
        var matchedPresets: Set<ActivityPreset> = []
        var remainingActivity = ""
        if let existingActivity = meeting.activity {
            let parts = existingActivity.components(separatedBy: ", ")
            for part in parts {
                if let matched = activityPresets.first(where: { $0.label == part }) {
                    matchedPresets.insert(matched)
                } else {
                    remainingActivity = part
                }
            }
        }
        _selectedPresets = State(initialValue: matchedPresets)
        _activity = State(initialValue: remainingActivity)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "모임 수정",
                backAction: onBack,
                trailingText: "완료",
                trailingAction: {
                    Haptic.medium()
                    if date < Date() {
                        showPastDateAlert = true
                    } else if willReactivate {
                        // cancelled/completed 모임을 미래로 옮기는 경우 한 번 더 확인.
                        // 가족 누군가의 실수로 종료된 모임이 silent로 살아나는 걸 방지.
                        showReactivateAlert = true
                    } else {
                        Task { await performSave() }
                    }
                },
                trailingDisabled: !canSave
            )

            ScrollView {
                VStack(spacing: 24) {
                    // 날짜 & 시간
                    VStack(alignment: .leading, spacing: 4) {
                        Text("날짜 & 시간")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .tint(AppColors.primary)
                            .labelsHidden()
                    }

                    // 장소 (단일 ↔ 후보 모드)
                    placeSection

                    // 활동 내용
                    VStack(alignment: .leading, spacing: 12) {
                        Text("활동 내용 (선택)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                        ], spacing: 10) {
                            ForEach(activityPresets) { preset in
                                let isSelected = selectedPresets.contains(preset)
                                Button {
                                    Haptic.light()
                                    if isSelected {
                                        selectedPresets.remove(preset)
                                    } else if selectedPresets.count < 4 {
                                        selectedPresets.insert(preset)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: preset.icon)
                                            .font(.body)
                                            .frame(width: 24)
                                        Text(preset.label)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(isSelected ? AppColors.primary : Color(.secondarySystemBackground))
                                    )
                                }
                            }
                        }

                        AppTextField(placeholder: "직접 입력", text: $activity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .task {
            if !placeURL.isEmpty { fetchLinkPreview(placeURL) }
            await loadExistingPoll()
        }
        .swipeBack(onBack: onBack)
        .alert("이미 지난 시점이에요", isPresented: $showPastDateAlert) {
            Button("취소", role: .cancel) {}
            Button("저장") { Task { await performSave() } }
        } message: {
            Text("선택한 일시가 현재 시점보다 과거입니다.\n저장하면 이 모임은 바로 완료된 모임으로 표시됩니다.")
        }
        .alert("이 모임을 다시 활성화할까요?", isPresented: $showReactivateAlert) {
            Button("취소", role: .cancel) {}
            Button("저장") { Task { await performSave() } }
        } message: {
            Text(reactivateAlertMessage)
        }
    }

    // MARK: - 장소 섹션

    @ViewBuilder
    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("장소")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Toggle(isOn: Binding(
                get: { useCandidates },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        useCandidates = newValue
                        if newValue && candidates.isEmpty {
                            // 새로 후보 모드 진입: 단일 장소를 첫 후보로 채워주면 부드러움
                            let seedTitle = place
                            let seedLink = placeURL
                            candidates = [
                                PlaceCandidateDraft(title: seedTitle, link: seedLink),
                                PlaceCandidateDraft(),
                            ]
                        } else if !newValue, let firstWithTitle = candidates.first(where: { !$0.title.isEmpty }) {
                            // 후보 모드 해제: 첫 유효 후보를 단일 장소로 시드
                            place = firstWithTitle.title
                            placeURL = firstWithTitle.link
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("여러 후보 올리고 가족 의견 받기")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("2~4개 후보를 올려 투표로 정해요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(AppColors.primary)
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if useCandidates {
                if isLoadingPoll {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("후보 불러오는 중...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    PlaceCandidatesEditor(candidates: $candidates)
                }
            } else {
                AppTextField(placeholder: "장소를 입력해주세요", text: $place)

                Text("장소 링크 (선택)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                AppTextField(placeholder: "네이버지도, 카카오맵 URL 붙여넣기", text: $placeURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .onChange(of: placeURL) { _, newValue in
                        handlePlaceURLChange(newValue)
                    }

                if isLoadingLink {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("링크 미리보기 로딩 중...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if let metadata = linkMetadata {
                    LinkPreviewCard(metadata: metadata)
                }
            }
        }
    }

    // MARK: - Poll 로드

    private func loadExistingPoll() async {
        guard meeting.hasPoll else { return }
        do {
            let polls = try await appState.getPolls(meetingId: meeting.id)
            if let poll = polls.first {
                initialPollId = poll.id
                candidates = poll.options.map(PlaceCandidateDraft.from)
                if candidates.count < 2 {
                    candidates.append(PlaceCandidateDraft())
                }
            } else {
                // hasPoll=true인데 실제 Poll이 없는 데이터 정합성 이슈 — 단일 모드로 폴백
                useCandidates = false
            }
        } catch {
            appState.error = AppError.from(error)
            useCandidates = false
        }
        isLoadingPoll = false
    }

    // MARK: - 저장

    @MainActor
    private func performSave() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        var updated = meeting
        updated.meetingDate = date
        updated.activity = finalActivity
        updated.updatedAt = Date()

        if useCandidates {
            updated.place = ""
            updated.placeURL = nil
            updated.hasPoll = true
        } else {
            updated.place = place
            updated.placeURL = placeURL.isEmpty ? nil : placeURL
            updated.hasPoll = false
        }

        // 일시가 미래로 옮겨졌으면 홈의 upcomingMeeting 필터에 다시 잡히게 status를 살린다.
        // (HomeView는 status==.planning|.confirmed 이고 meetingDate>now 인 모임만 다음 모임으로 뽑음)
        if date > Date() && (updated.status == .completed || updated.status == .cancelled) {
            updated.status = .planning
        }

        do {
            try await appState.updateMeeting(updated)

            // Poll 라이프사이클
            switch (initialPollId, useCandidates) {
            case (nil, true):
                let poll = Poll(
                    id: UUID().uuidString,
                    question: "어디로 갈까요?",
                    isAnonymous: false,
                    allowMultiple: true,
                    options: validCandidateOptions,
                    createdAt: Date()
                )
                _ = try await appState.createPoll(meetingId: updated.id, poll: poll)
            case (let pollId?, true):
                try await appState.updatePollOptions(
                    meetingId: updated.id,
                    pollId: pollId,
                    options: validCandidateOptions
                )
            case (let pollId?, false):
                try await appState.deletePoll(meetingId: updated.id, pollId: pollId)
            case (nil, false):
                break
            }

            onSaved(updated)
        } catch {
            appState.error = AppError.from(error)
        }
    }

    // MARK: - 링크 헬퍼

    private func handlePlaceURLChange(_ newValue: String) {
        if let extracted = URLExtractor.firstURL(in: newValue),
           extracted.absoluteString != newValue {
            placeURL = extracted.absoluteString
            return
        }
        fetchLinkPreview(newValue)
    }

    private func fetchLinkPreview(_ urlString: String) {
        linkMetadata = nil
        guard let url = URLExtractor.firstURL(in: urlString) else { return }

        isLoadingLink = true
        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { metadata, _ in
            DispatchQueue.main.async {
                isLoadingLink = false
                linkMetadata = metadata
            }
        }
    }
}

#Preview {
    EditMeetingView(meeting: MockData.meetings[0], onBack: {}, onSaved: { _ in })
}
