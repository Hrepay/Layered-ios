import SwiftUI

struct CreateRecordView: View {
    let meeting: Meeting
    let existingRecord: MeetingRecord?
    let onBack: () -> Void
    let onSaved: (MeetingRecord) -> Void

    @Environment(AppState.self) private var appState: AppState

    @State private var photos: [RecordPhotoSlot]
    @State private var removedExistingURLs: [String] = []
    @State private var comment: String
    @State private var rating: Int
    @State private var animatedStar: Int? = nil
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var showExitAlert = false
    @State private var showAttendanceBanner = false
    @State private var isUpdatingAttendance = false
    @FocusState private var commentFocused: Bool

    private var isEditMode: Bool { existingRecord != nil }

    init(
        meeting: Meeting,
        existingRecord: MeetingRecord? = nil,
        onBack: @escaping () -> Void,
        onSaved: @escaping (MeetingRecord) -> Void
    ) {
        self.meeting = meeting
        self.existingRecord = existingRecord
        self.onBack = onBack
        self.onSaved = onSaved
        _comment = State(initialValue: existingRecord?.comment ?? "")
        _rating = State(initialValue: existingRecord?.rating ?? 0)
        _photos = State(initialValue: existingRecord?.photos.map { RecordPhotoSlot(content: .existing(url: $0)) } ?? [])
    }

    private var hasUnsavedChanges: Bool {
        if let existing = existingRecord {
            let keptURLs = photos.compactMap { slot -> String? in
                if case .existing(let url) = slot.content { return url } else { return nil }
            }
            let hasNewPhotos = photos.contains { if case .new = $0.content { return true } else { return false } }
            return comment != existing.comment
                || rating != existing.rating
                || keptURLs != existing.photos
                || hasNewPhotos
        } else {
            return !comment.isEmpty || rating > 0 || !photos.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: isEditMode ? "기록 수정" : "모임 기록",
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
                    Task { await save() }
                },
                trailingDisabled: !isValid || isUploading
            )

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - 참석 확인 배너 (미정·불참 상태에서 기록 쓸 때 한 번만)
                    if showAttendanceBanner {
                        attendanceBanner
                    }

                    // MARK: - 모임 요약 카드
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppColors.primary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(meeting.displayPlace)
                                .font(.headline)

                            Text(formatDate(meeting.meetingDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .card()

                    // MARK: - 사진 첨부
                    VStack(alignment: .leading, spacing: 10) {
                        Text("사진 (최대 3장)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { index in
                                if index < photos.count {
                                    ZStack(alignment: .topTrailing) {
                                        photoThumbnail(for: photos[index])
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))

                                        Button {
                                            Haptic.light()
                                            removePhoto(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.body)
                                                .foregroundStyle(.white)
                                                .background(Circle().fill(.black.opacity(0.5)))
                                        }
                                        .padding(4)
                                    }
                                } else if index == photos.count && photos.count < 3 {
                                    Button {
                                        Haptic.light()
                                        showImagePicker = true
                                    } label: {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                style: StrokeStyle(lineWidth: 1.5, dash: [6])
                                            )
                                            .foregroundStyle(Color(.systemGray3))
                                            .aspectRatio(1, contentMode: .fit)
                                            .overlay {
                                                Image(systemName: "plus")
                                                    .font(.title3)
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }
                        }
                    }

                    // MARK: - 별점
                    VStack(alignment: .leading, spacing: 10) {
                        Text("별점")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    Haptic.starRating(star)
                                    withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                                        rating = star
                                        animatedStar = star
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        animatedStar = nil
                                    }
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.title2)
                                        .foregroundStyle(star <= rating ? AppColors.warning : Color(.systemGray4))
                                        .scaleEffect(animatedStar == star ? 1.3 : 1.0)
                                        .animation(.spring(duration: 0.3, bounce: 0.5), value: animatedStar)
                                }
                            }

                            Spacer()
                        }
                    }

                    // MARK: - 한 줄 소감
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("한 줄 소감")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(comment.count)/1000")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $comment)
                            .frame(minHeight: 120)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .focused($commentFocused)
                            .id("comment")
                            .onChange(of: comment) { _, newValue in
                                if newValue.count > 1000 {
                                    comment = String(newValue.prefix(1000))
                                }
                            }
                    }
                    .id("commentSection")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .onChange(of: commentFocused) { _, focused in
                if focused {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("commentSection", anchor: .bottom)
                    }
                }
            }
            .onChange(of: comment) { _, _ in
                if commentFocused {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("commentSection", anchor: .bottom)
                    }
                }
            }
            }
        }
        .loadingOverlay(isUploading)
        .onAppear {
            // 내 참석 상태가 .going이 아니면(미정·불참 포함) 참석 확인 배너 표시.
            // 기존 기록 수정 모드면 이미 참석했다는 의미이므로 묻지 않음.
            guard !isEditMode, let userId = appState.currentUser?.id else { return }
            if meeting.attendanceStatus(for: userId) != .going {
                withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                    showAttendanceBanner = true
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            MultiImagePicker(maxSelection: 3 - photos.count, selectedImages: Binding(
                get: { [] },
                set: { newImages in
                    let available = 3 - photos.count
                    for image in newImages.prefix(available) {
                        photos.append(RecordPhotoSlot(content: .new(image: image)))
                    }
                }
            ))
        }
        .alert("저장되지 않아요", isPresented: $showExitAlert) {
            Button("취소", role: .cancel) {}
            Button("나가기", role: .destructive) { onBack() }
        } message: {
            Text("지금 나가면 입력한 내용이 저장되지 않습니다.")
        }
    }

    // MARK: - 참석 확인 배너
    /// 참석 미정·불참 상태에서 기록을 쓰러 들어왔을 때 한 번 확인 후 자동으로 참석으로 갱신.
    /// "예"를 누르면 setMyAttendance(.going) 호출, 둘 다 누르면 배너만 사라지고 기록은 그대로 계속.
    @ViewBuilder
    private var attendanceBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("이 모임에 참석하셨어요?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("기록을 남기려면 참석으로 표시해야 자연스러워요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    Haptic.light()
                    Task { await confirmAttended() }
                } label: {
                    Text("예, 참석했어요")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                }
                .disabled(isUpdatingAttendance)

                Button {
                    Haptic.light()
                    withAnimation(.spring(duration: 0.3)) {
                        showAttendanceBanner = false
                    }
                } label: {
                    Text("아니요")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
                .disabled(isUpdatingAttendance)
            }
        }
        .card(highlighted: true)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.95))
        ))
    }

    @MainActor
    private func confirmAttended() async {
        Haptic.medium()
        isUpdatingAttendance = true
        defer { isUpdatingAttendance = false }
        do {
            try await appState.setMyAttendance(meetingId: meeting.id, status: .going)
            Haptic.success()
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                showAttendanceBanner = false
            }
        } catch {
            appState.error = AppError.from(error)
        }
    }

    @ViewBuilder
    private func photoThumbnail(for slot: RecordPhotoSlot) -> some View {
        switch slot.content {
        case .existing(let url):
            CachedAsyncImage(url: URL(string: url))
                .aspectRatio(1, contentMode: .fill)
        case .new(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }

    private func removePhoto(at index: Int) {
        Haptic.light()
        let removed = photos.remove(at: index)
        if case .existing(let url) = removed.content {
            removedExistingURLs.append(url)
        }
    }

    private var isValid: Bool {
        rating > 0 && !comment.isEmpty
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }

    // MARK: - Save
    private func save() async {
        isUploading = true
        defer { isUploading = false }

        do {
            if let existing = existingRecord {
                try await saveEdit(existing: existing)
            } else {
                try await saveCreate()
            }
        } catch {
            appState.error = AppError.from(error)
        }
    }

    private func saveCreate() async throws {
        guard let familyId = appState.currentFamily?.id else { return }
        let recordId = UUID().uuidString
        var photoURLs: [String] = []
        for (index, slot) in photos.enumerated() {
            if case .new(let image) = slot.content,
               let data = ImageProcessor.resizeAndCompress(image) {
                let url = try await appState.storageRepository.uploadRecordPhoto(
                    familyId: familyId,
                    meetingId: meeting.id,
                    recordId: recordId,
                    index: index,
                    imageData: data
                )
                photoURLs.append(url)
            }
        }
        let record = MeetingRecord(
            id: recordId,
            memberId: appState.currentUser?.id ?? "",
            memberName: appState.currentUser?.name ?? "",
            photos: photoURLs,
            comment: comment,
            rating: rating,
            createdAt: Date(),
            updatedAt: Date()
        )
        let created = try await appState.createRecord(meetingId: meeting.id, record: record)
        onSaved(created)
    }

    private func saveEdit(existing: MeetingRecord) async throws {
        guard let familyId = appState.currentFamily?.id else { return }

        // 변경 사항 없으면 Firestore write 생략
        guard hasUnsavedChanges else {
            onSaved(existing)
            return
        }

        // 1) 신규 사진 업로드 (인덱스 충돌 방지를 위해 타임스탬프 기반 키 사용)
        let baseIndex = Int(Date().timeIntervalSince1970)
        var newURLs: [String] = []
        var newCounter = 0
        for slot in photos {
            if case .new(let image) = slot.content,
               let data = ImageProcessor.resizeAndCompress(image) {
                let url = try await appState.storageRepository.uploadRecordPhoto(
                    familyId: familyId,
                    meetingId: meeting.id,
                    recordId: existing.id,
                    index: baseIndex + newCounter,
                    imageData: data
                )
                newURLs.append(url)
                newCounter += 1
            }
        }

        // 2) 최종 사진 URL 배열을 슬롯 순서대로 조립
        var finalURLs: [String] = []
        var newCursor = 0
        for slot in photos {
            switch slot.content {
            case .existing(let url):
                finalURLs.append(url)
            case .new:
                finalURLs.append(newURLs[newCursor])
                newCursor += 1
            }
        }

        // 3) Firestore 업데이트
        let updated = MeetingRecord(
            id: existing.id,
            memberId: existing.memberId,
            memberName: existing.memberName,
            photos: finalURLs,
            comment: comment,
            rating: rating,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        try await appState.updateRecord(meetingId: meeting.id, record: updated)

        // 4) 제거된 기존 사진은 Storage에서 정리 (실패해도 본 작업은 성공)
        for url in removedExistingURLs {
            try? await appState.storageRepository.deletePhotoByURL(url)
        }

        onSaved(updated)
    }
}

struct RecordPhotoSlot {
    let content: Content

    enum Content {
        case existing(url: String)
        case new(image: UIImage)
    }
}

#Preview("기록 작성") {
    CreateRecordView(meeting: MockData.meetings[1], onBack: {}, onSaved: { _ in })
        .environment(AppState())
}

/// 별점 단계별 햅틱과 spring 튕김을 빠르게 확인하기 위한 미니멀 데모.
/// 실제 화면 노이즈 없이 별 5개만 띄우고, 탭하면 단계별 햅틱(1·2 light → 3 medium → 4 heavy → 5 heavy+success)이 발화.
#Preview("별점 햅틱 데모") {
    StarRatingHapticDemo()
}

private struct StarRatingHapticDemo: View {
    @State private var rating = 0
    @State private var animatedStar: Int? = nil

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text("별점 단계별 햅틱")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("탭해서 1~5★ 강도 차이를 확인")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        Haptic.starRating(star)
                        withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                            rating = star
                            animatedStar = star
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            animatedStar = nil
                        }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 36))
                            .foregroundStyle(star <= rating ? AppColors.warning : Color(.systemGray4))
                            .scaleEffect(animatedStar == star ? 1.3 : 1.0)
                            .animation(.spring(duration: 0.3, bounce: 0.5), value: animatedStar)
                    }
                }
            }

            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 20)

            Button("초기화") {
                withAnimation { rating = 0 }
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var hint: String {
        switch rating {
        case 0: return ""
        case 1, 2: return "light · 가벼운 탁"
        case 3: return "medium · 무게감 있는 탁"
        case 4: return "heavy · 묵직한 탁"
        case 5: return "heavy + success · 5★ 성공 알림"
        default: return ""
        }
    }
}
