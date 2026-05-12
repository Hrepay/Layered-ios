import SwiftUI

struct RecordDetailView: View {
    let meeting: Meeting
    let onBack: () -> Void
    var onDeleted: (() -> Void)?

    @Environment(AppState.self) private var appState: AppState

    @State private var records: [MeetingRecord] = []
    @State private var showRecordDeleteAlert = false
    @State private var showMeetingDeleteAlert = false
    @State private var recordToDelete: MeetingRecord?
    @State private var recordToEdit: MeetingRecord?
    @State private var showCreateRecord = false
    @State private var fullScreenImageURL: String?
    @State private var showMeetingDetail = false

    private var hasMyRecord: Bool {
        guard let userId = appState.currentUser?.id else { return false }
        return records.contains { $0.memberId == userId }
    }

    private var canDeleteMeeting: Bool {
        guard let userId = appState.currentUser?.id else { return false }
        return meeting.plannerId == userId
    }

    private var trailingMenu: AnyView? {
        guard canDeleteMeeting else { return nil }
        return AnyView(
            Menu {
                Button("모임 삭제", systemImage: "trash.fill", role: .destructive) {
                    showMeetingDeleteAlert = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "모임 기록",
                backAction: onBack,
                trailingMenu: trailingMenu
            )

            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - 모임 요약 카드 (탭하면 모임 상세)
                    Button {
                        Haptic.light()
                        showMeetingDetail = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppColors.primary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(meeting.displayPlace)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(formatDate(meeting.meetingDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)

                    // MARK: - 구성원별 기록
                    if records.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color(.systemGray4))
                            Text("아직 기록이 없어요")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .card()
                    } else {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    AvatarView(
                                        name: record.memberName,
                                        size: 36,
                                        imageURL: appState.members.first(where: { $0.id == record.memberId })?.profileImageURL
                                    )

                                    Text(record.memberName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Spacer()

                                    HStack(spacing: 2) {
                                        ForEach(1...5, id: \.self) { star in
                                            Image(systemName: star <= record.rating ? "star.fill" : "star")
                                                .font(.caption2)
                                                .foregroundStyle(star <= record.rating ? AppColors.warning : Color(.systemGray4))
                                        }
                                    }

                                    if record.memberId == appState.currentUser?.id {
                                        Menu {
                                            Button("수정", systemImage: "pencil") {
                                                Haptic.light()
                                                recordToEdit = record
                                            }
                                            Button("삭제", systemImage: "trash.fill", role: .destructive) {
                                                recordToDelete = record
                                                showRecordDeleteAlert = true
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 28, height: 28)
                                        }
                                    }
                                }

                                // 사진
                                if !record.photos.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(record.photos, id: \.self) { url in
                                                Button {
                                                    fullScreenImageURL = url
                                                } label: {
                                                    CachedAsyncImage(url: URL(string: url))
                                                        .frame(width: 100, height: 100)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                                }
                                            }
                                        }
                                    }
                                }

                                Text(record.comment)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .card()
                        }
                    }

                    // MARK: - 기록하기 버튼 (내 기록 없을 때)
                    if !hasMyRecord {
                        let isPast = meeting.meetingDate <= Date()
                        Button(action: {
                            Haptic.medium()
                            showCreateRecord = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(isPast ? AppColors.primary : .gray)
                                Text(isPast ? "나도 기록하기" : "모임 후 기록할 수 있어요")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(isPast ? .primary : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isPast ? AppColors.primarySubtle : Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(!isPast)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .refreshable {
                await loadRecords()
            }
        }
        .task {
            await loadRecords()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showMeetingDetail) {
            MeetingDetailView(
                meeting: meeting,
                onBack: { showMeetingDetail = false },
                showsActionMenu: false
            )
            .environment(appState)
        }
        .fullScreenCover(isPresented: $showCreateRecord) {
            CreateRecordView(meeting: meeting, onBack: {
                showCreateRecord = false
            }, onSaved: { _ in
                showCreateRecord = false
                Task { await loadRecords() }
            })
            .environment(appState)
        }
        .fullScreenCover(item: $recordToEdit) { record in
            CreateRecordView(
                meeting: meeting,
                existingRecord: record,
                onBack: { recordToEdit = nil },
                onSaved: { _ in
                    recordToEdit = nil
                    Task { await loadRecords() }
                }
            )
            .environment(appState)
        }
        .alert("기록 삭제", isPresented: $showRecordDeleteAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                if let record = recordToDelete {
                    Task {
                        do {
                            try await appState.deleteRecord(meetingId: meeting.id, recordId: record.id)
                            await loadRecords()
                        } catch {
                            appState.error = AppError.from(error)
                        }
                    }
                }
            }
        } message: {
            Text("이 기록을 삭제하시겠습니까?")
        }
        .alert("모임 삭제", isPresented: $showMeetingDeleteAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                Task {
                    do {
                        try await appState.deleteMeeting(meeting.id)
                        onDeleted?()
                    } catch {
                        appState.error = AppError.from(error)
                    }
                }
            }
        } message: {
            Text("모임과 관련된 모든 기록·사진이 영구 삭제됩니다.\n이 작업은 되돌릴 수 없습니다.")
        }
        .fullScreenCover(item: Binding(
            get: { fullScreenImageURL.map { FullScreenImageItem(url: $0) } },
            set: { fullScreenImageURL = $0?.url }
        )) { item in
            FullScreenImageView(url: item.url, onDismiss: { fullScreenImageURL = nil })
        }
        .swipeBack(onBack: onBack)
    }

    private func loadRecords() async {
        records = (try? await appState.getRecords(meetingId: meeting.id)) ?? []
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }
}

#Preview("모임 기록 상세") {
    RecordDetailView(meeting: MockData.meetings[1], onBack: {})
}
