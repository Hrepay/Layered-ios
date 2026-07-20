import SwiftUI

/// "한 겹 남기기" — 모임으로 정하기 애매하거나 그냥 지나간 주에 한 줄 + 선택 사진 1장만 가볍게 남기는 화면.
/// 텍스트필드 화면이라 주요 액션(완료)은 키보드 가림 방지를 위해 상단 네비바에 둔다.
struct CreateNoteView: View {
    let existingNote: Note?
    let onBack: () -> Void
    let onSaved: (Note) -> Void

    @Environment(AppState.self) private var appState: AppState

    @State private var text: String
    @State private var date: Date
    @State private var photo: PhotoSlot?
    /// 함께한 사람. 비어 있으면 작성자만.
    @State private var participantIds: [String]
    /// 수정 모드에서 기존 사진을 지운 경우 Storage 정리 대상 URL.
    @State private var removedExistingURL: String?
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var showExitAlert = false
    @FocusState private var textFocused: Bool

    private let maxLength = 300

    private var isEditMode: Bool { existingNote != nil }

    init(
        existingNote: Note? = nil,
        onBack: @escaping () -> Void,
        onSaved: @escaping (Note) -> Void
    ) {
        self.existingNote = existingNote
        self.onBack = onBack
        self.onSaved = onSaved
        _text = State(initialValue: existingNote?.text ?? "")
        _date = State(initialValue: existingNote?.date ?? Date())
        _photo = State(initialValue: existingNote?.photoURL.map { PhotoSlot(content: .existing(url: $0)) })
        _participantIds = State(initialValue: existingNote?.participantIds ?? [])
    }

    private var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasUnsavedChanges: Bool {
        if let existing = existingNote {
            let keptURL: String? = {
                if case .existing(let url) = photo?.content { return url } else { return nil }
            }()
            let hasNewPhoto: Bool = {
                if case .new = photo?.content { return true } else { return false }
            }()
            return text != existing.text
                || !Calendar.current.isDate(date, inSameDayAs: existing.date)
                || keptURL != existing.photoURL
                || hasNewPhoto
                || Set(participantIds) != Set(existing.participantIds)
        } else {
            return !text.isEmpty || photo != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: isEditMode ? "한 겹 수정" : "한 겹 남기기",
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

            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - 안내
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.title2)
                            .foregroundStyle(AppColors.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("오늘을 한 줄로")
                                .font(.headline)
                            Text("모임이 아니어도, 남기고 싶은 순간을 가볍게 적어요")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .card()

                    // MARK: - 날짜
                    HStack {
                        Text("날짜")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        DatePicker(
                            "",
                            selection: $date,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ko_KR"))
                    }

                    // MARK: - 함께한 사람
                    VStack(alignment: .leading, spacing: 10) {
                        Text("함께한 사람")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            ForEach(appState.members) { member in
                                participantRow(member)
                            }
                        }
                    }

                    // MARK: - 메모
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("메모")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(text.count)/\(maxLength)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .focused($textFocused)
                            .overlay(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text("예) 이번 주는 못 모였지만, 아빠가 김치찌개 끓여줌 🍲")
                                        .font(.body)
                                        .foregroundStyle(Color(.placeholderText))
                                        .padding(.horizontal, 17)
                                        .padding(.vertical, 20)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onChange(of: text) { _, newValue in
                                if newValue.count > maxLength {
                                    text = String(newValue.prefix(maxLength))
                                }
                            }
                    }

                    // MARK: - 사진 (선택, 1장)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("사진 (선택)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        if let photo {
                            ZStack(alignment: .topTrailing) {
                                photoThumbnail(for: photo)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))

                                Button {
                                    Haptic.light()
                                    removePhoto()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .background(Circle().fill(.black.opacity(0.5)))
                                }
                                .padding(8)
                            }
                        } else {
                            Button {
                                Haptic.light()
                                showImagePicker = true
                            } label: {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                    .foregroundStyle(Color(.systemGray3))
                                    .frame(height: 120)
                                    .overlay {
                                        VStack(spacing: 6) {
                                            Image(systemName: "photo.badge.plus")
                                                .font(.title2)
                                            Text("사진 추가")
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .loadingOverlay(isUploading)
        .onAppear {
            // 신규 작성이면 작성자 본인을 기본 참여자로 선택.
            if !isEditMode, participantIds.isEmpty, let uid = appState.currentUser?.id {
                participantIds = [uid]
            }
        }
        .sheet(isPresented: $showImagePicker) {
            MultiImagePicker(maxSelection: 1, selectedImages: Binding(
                get: { [] },
                set: { newImages in
                    if let image = newImages.first {
                        photo = PhotoSlot(content: .new(image: image))
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

    @ViewBuilder
    private func photoThumbnail(for slot: PhotoSlot) -> some View {
        switch slot.content {
        case .existing(let url):
            CachedAsyncImage(url: URL(string: url))
                .aspectRatio(contentMode: .fill)
        case .new(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }

    private func removePhoto() {
        Haptic.light()
        if case .existing(let url) = photo?.content {
            removedExistingURL = url
        }
        photo = nil
    }

    // MARK: - 참여자 선택
    @ViewBuilder
    private func participantRow(_ member: Member) -> some View {
        let on = participantIds.contains(member.id)
        Button {
            Haptic.light()
            toggleParticipant(member.id)
        } label: {
            HStack(spacing: 10) {
                AvatarView(name: member.name, size: 32, imageURL: member.profileImageURL)
                Text(member.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? AppColors.secondary : Color(.systemGray4))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(on ? AppColors.secondarySubtle : Color(.secondarySystemBackground))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleParticipant(_ id: String) {
        if let idx = participantIds.firstIndex(of: id) {
            participantIds.remove(at: idx)
        } else {
            participantIds.append(id)
        }
    }

    // MARK: - Save
    private func save() async {
        isUploading = true
        defer { isUploading = false }
        do {
            if let existing = existingNote {
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
        let noteId = UUID().uuidString
        var photoURL: String?
        if case .new(let image) = photo?.content,
           let data = ImageProcessor.resizeAndCompress(image) {
            photoURL = try await appState.storageRepository.uploadNotePhoto(
                familyId: familyId,
                noteId: noteId,
                imageData: data
            )
        }
        let note = Note(
            id: noteId,
            authorId: appState.currentUser?.id ?? "",
            authorName: appState.currentUser?.name ?? "",
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            photoURL: photoURL,
            participantIds: participantIds,
            date: date,
            createdAt: Date(),
            updatedAt: Date()
        )
        let created = try await appState.createNote(note)
        onSaved(created)
    }

    private func saveEdit(existing: Note) async throws {
        guard let familyId = appState.currentFamily?.id else { return }
        guard hasUnsavedChanges else {
            onSaved(existing)
            return
        }

        // 최종 사진 URL 결정
        var finalURL: String?
        switch photo?.content {
        case .existing(let url):
            finalURL = url
        case .new(let image):
            if let data = ImageProcessor.resizeAndCompress(image) {
                finalURL = try await appState.storageRepository.uploadNotePhoto(
                    familyId: familyId,
                    noteId: existing.id,
                    imageData: data
                )
            }
        case .none:
            finalURL = nil
        }

        let updated = Note(
            id: existing.id,
            authorId: existing.authorId,
            authorName: existing.authorName,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            photoURL: finalURL,
            participantIds: participantIds,
            date: date,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        try await appState.updateNote(updated)

        // 제거된 기존 사진 Storage 정리 (실패해도 본 작업은 성공)
        if let removed = removedExistingURL, removed != finalURL {
            try? await appState.storageRepository.deletePhotoByURL(removed)
        }

        onSaved(updated)
    }

    struct PhotoSlot {
        let content: Content
        enum Content {
            case existing(url: String)
            case new(image: UIImage)
        }
    }
}

#Preview("한 겹 작성") {
    CreateNoteView(onBack: {}, onSaved: { _ in })
        .environment(AppState())
}
