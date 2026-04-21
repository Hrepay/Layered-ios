import SwiftUI

struct CreateRecordView: View {
    let meeting: Meeting
    let onBack: () -> Void
    let onSaved: (MeetingRecord) -> Void

    @Environment(AppState.self) private var appState: AppState

    @State private var comment = ""
    @State private var rating = 0
    @State private var selectedImages: [UIImage] = []
    @State private var animatedStar: Int? = nil
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var showExitAlert = false
    @FocusState private var commentFocused: Bool

    private var hasUnsavedChanges: Bool {
        !comment.isEmpty || rating > 0 || !selectedImages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "모임 기록",
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
                    isUploading = true
                    let recordId = UUID().uuidString
                    Task {
                        do {
                            var photoURLs: [String] = []
                            if let familyId = appState.currentFamily?.id {
                                for (index, image) in selectedImages.enumerated() {
                                    guard let data = ImageProcessor.resizeAndCompress(image) else { continue }
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
                            isUploading = false
                            onSaved(record)
                        } catch {
                            isUploading = false
                            appState.error = AppError.from(error)
                        }
                    }
                },
                trailingDisabled: !isValid || isUploading
            )

            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
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
                                if index < selectedImages.count {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selectedImages[index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fit)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))

                                        Button {
                                            selectedImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.body)
                                                .foregroundStyle(.white)
                                                .background(Circle().fill(.black.opacity(0.5)))
                                        }
                                        .padding(4)
                                    }
                                } else if index == selectedImages.count && selectedImages.count < 3 {
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
                                    Haptic.light()
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
        .sheet(isPresented: $showImagePicker) {
            MultiImagePicker(maxSelection: 3 - selectedImages.count, selectedImages: Binding(
                get: { [] },
                set: { newImages in
                    selectedImages.append(contentsOf: newImages.prefix(3 - selectedImages.count))
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

    private var isValid: Bool {
        rating > 0 && !comment.isEmpty
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }
}

#Preview("기록 작성") {
    CreateRecordView(meeting: MockData.meetings[1], onBack: {}, onSaved: { _ in })
}
