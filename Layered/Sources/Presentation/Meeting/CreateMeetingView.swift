import SwiftUI
import LinkPresentation

// MARK: - 활동 프리셋
struct ActivityPreset: Identifiable, Hashable {
    let id = UUID()
    let icon: String
    let label: String
}

let activityPresets: [ActivityPreset] = [
    ActivityPreset(icon: "fork.knife", label: "외식"),
    ActivityPreset(icon: "cup.and.saucer.fill", label: "카페"),
    ActivityPreset(icon: "film.fill", label: "영화"),
    ActivityPreset(icon: "figure.walk", label: "산책"),
    ActivityPreset(icon: "figure.run", label: "운동"),
    ActivityPreset(icon: "leaf.fill", label: "피크닉"),
    ActivityPreset(icon: "cart.fill", label: "쇼핑"),
    ActivityPreset(icon: "house.fill", label: "집에서"),
    ActivityPreset(icon: "gamecontroller.fill", label: "게임"),
    ActivityPreset(icon: "book.fill", label: "문화생활"),
]

struct CreateMeetingView: View {
    let onBack: () -> Void
    let onCreated: (Meeting, Poll?) -> Void
    @Environment(AppState.self) private var appState: AppState

    @State private var date = Date()
    // 단일 장소 모드
    @State private var place = ""
    @State private var placeURL = ""
    // 후보 모드
    @State private var useCandidates = false
    @State private var candidates: [PlaceCandidateDraft] = [PlaceCandidateDraft(), PlaceCandidateDraft()]
    @State private var activity = ""
    @State private var selectedPresets: Set<ActivityPreset> = []
    @State private var linkMetadata: LPLinkMetadata?
    @State private var isLoadingLink = false
    @State private var showExitAlert = false

    private var finalActivity: String? {
        let presetLabels = selectedPresets.map(\.label)
        let combined = activity.isEmpty ? presetLabels : presetLabels + [activity]
        return combined.isEmpty ? nil : combined.joined(separator: ", ")
    }

    private var validCandidateOptions: [PollOption] {
        PlaceCandidateDraft.toPollOptions(candidates)
    }

    private var hasUnsavedChanges: Bool {
        if useCandidates {
            return !candidates.allSatisfy { $0.title.isEmpty && $0.link.isEmpty }
        }
        return !place.isEmpty || !placeURL.isEmpty || !activity.isEmpty || !selectedPresets.isEmpty
    }

    private var canSave: Bool {
        if useCandidates {
            return validCandidateOptions.count >= 2
        }
        return !place.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "모임 계획하기",
                backAction: {
                    if hasUnsavedChanges {
                        showExitAlert = true
                    } else {
                        onBack()
                    }
                },
                trailingText: "완료",
                trailingAction: {
                    Haptic.medium()
                    let (savedPlace, savedPlaceURL, hasPoll, poll) = buildSaveState()
                    let meeting = Meeting(
                        id: UUID().uuidString,
                        plannerId: appState.currentUser?.id ?? "",
                        plannerName: appState.currentUser?.name ?? "",
                        meetingDate: date,
                        place: savedPlace,
                        placeLatitude: nil,
                        placeLongitude: nil,
                        placeURL: savedPlaceURL,
                        activity: finalActivity,
                        status: .planning,
                        hasPoll: hasPoll,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    onCreated(meeting, poll)
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

                        DatePicker("", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
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

                        // 프리셋 그리드 (다중 선택)
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

                        // 직접 입력
                        AppTextField(placeholder: "직접 입력", text: $activity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .alert("저장되지 않아요", isPresented: $showExitAlert) {
            Button("취소", role: .cancel) {}
            Button("나가기", role: .destructive) { onBack() }
        } message: {
            Text("지금 나가면 입력한 내용이 저장되지 않습니다.")
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

            // 모드 토글
            Toggle(isOn: $useCandidates.animation(.easeInOut(duration: 0.2))) {
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
                PlaceCandidatesEditor(candidates: $candidates)
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
                        ProgressView()
                            .scaleEffect(0.8)
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

    // MARK: - Save build

    private func buildSaveState() -> (place: String, placeURL: String?, hasPoll: Bool, poll: Poll?) {
        if useCandidates {
            let options = validCandidateOptions
            let poll = Poll(
                id: UUID().uuidString,
                question: "어디로 갈까요?",
                isAnonymous: false,
                allowMultiple: true,
                options: options,
                createdAt: Date()
            )
            return ("", nil, true, poll)
        } else {
            return (place, placeURL.isEmpty ? nil : placeURL, false, nil)
        }
    }

    // MARK: - Helpers

    /// 텍스트 변경 시: 여러 줄 텍스트가 들어오면 URL만 추출해서 필드를 갈아끼우고, 그 URL로 미리보기 요청
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

// MARK: - 홈 카드 전용 이미지 미리보기 (LPLinkMetadata에서 이미지만 추출)
struct LinkPreviewImage: View {
    let metadata: LPLinkMetadata
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(.systemGray5)
            }
        }
        .task(id: metadata.originalURL) {
            guard let provider = metadata.imageProvider else { return }
            let loaded: UIImage? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
            await MainActor.run { self.image = loaded }
        }
    }
}

// MARK: - 링크 미리보기 (LPLinkView 래핑 — 타이틀·도메인 포함 리치 프리뷰)
struct LinkPreviewCard: UIViewRepresentable {
    let metadata: LPLinkMetadata

    func makeUIView(context: Context) -> LPLinkView {
        let linkView = LPLinkView(metadata: metadata)
        linkView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return linkView
    }

    func updateUIView(_ uiView: LPLinkView, context: Context) {
        uiView.metadata = metadata
    }
}

#Preview {
    CreateMeetingView(onBack: {}, onCreated: { _, _ in })
}
