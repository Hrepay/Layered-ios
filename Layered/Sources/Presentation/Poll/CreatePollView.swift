import SwiftUI

struct CreatePollView: View {
    let onBack: () -> Void
    let onCreated: (Poll) -> Void

    @Environment(AppState.self) private var appState: AppState

    struct OptionDraft: Identifiable {
        let id = UUID()
        var title: String = ""
        var link: String = ""
    }

    @State private var question = ""
    @State private var options: [OptionDraft] = [OptionDraft(), OptionDraft()]
    @State private var isAnonymous = false
    /// 장소 검색 시트가 채울 선택지 인덱스. nil이면 시트 닫힘.
    @State private var searchingIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "투표 만들기",
                backAction: onBack,
                trailingText: "완료",
                trailingAction: {
                    Haptic.medium()
                    let pollOptions = options.compactMap { draft -> PollOption? in
                        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return nil }
                        let linkURL = URLExtractor.firstURL(in: draft.link)?.absoluteString
                        return PollOption(
                            id: UUID().uuidString,
                            title: title,
                            description: nil,
                            imageURL: nil,
                            linkURL: linkURL,
                            voterIds: [],
                            voteCount: 0
                        )
                    }
                    let poll = Poll(
                        id: UUID().uuidString,
                        question: question,
                        isAnonymous: isAnonymous,
                        allowMultiple: true,
                        options: pollOptions,
                        createdAt: Date()
                    )
                    onCreated(poll)
                },
                trailingDisabled: !isValid
            )

            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - 투표 제목
                    VStack(alignment: .leading, spacing: 8) {
                        Text("투표 제목")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        AppTextField(placeholder: "예: 어디로 갈까요?", text: $question)
                    }

                    // MARK: - 선택지
                    VStack(alignment: .leading, spacing: 16) {
                        Text("선택지")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        ForEach(options.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    AppTextField(
                                        placeholder: "선택지 \(index + 1)",
                                        text: $options[index].title
                                    )

                                    Button {
                                        Haptic.light()
                                        searchingIndex = index
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(AppColors.primary)
                                            .frame(width: 44, height: 44)
                                            .background(AppColors.primarySubtle)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }

                                    if options.count > 2 {
                                        Button {
                                            Haptic.light()
                                            _ = withAnimation(.spring(duration: 0.25)) {
                                                options.remove(at: index)
                                            }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(AppColors.danger)
                                        }
                                    }
                                }

                                AppTextField(
                                    placeholder: "링크 (선택)",
                                    text: $options[index].link
                                )
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .onChange(of: options[index].link) { _, newValue in
                                    handleLinkChange(index: index, newValue: newValue)
                                }

                                // 붙여넣은 즉시 인식한 URL을 칩으로 표시 (탭 시 열림)
                                if let url = URLExtractor.firstURL(in: options[index].link) {
                                    Link(destination: url) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "link")
                                                .font(.caption2)
                                                .foregroundStyle(AppColors.primary)
                                            Text(url.host ?? url.absoluteString)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .foregroundStyle(.primary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(AppColors.primarySubtle)
                                        )
                                    }
                                }
                            }
                        }

                        if options.count < 4 {
                            Button {
                                Haptic.light()
                                withAnimation(.spring(duration: 0.25)) {
                                    options.append(OptionDraft())
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(AppColors.primary)
                                    Text("선택지 추가")
                                        .foregroundStyle(.primary)
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                            }
                            .padding(.top, 4)
                        }
                    }

                    // MARK: - 익명 투표
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("익명 투표")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("누가 투표했는지 비공개로 진행돼요")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $isAnonymous)
                            .labelsHidden()
                            .tint(AppColors.primary)
                    }
                    .card()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .swipeBack(onBack: onBack)
        .sheet(isPresented: Binding(
            get: { searchingIndex != nil },
            set: { if !$0 { searchingIndex = nil } }
        )) {
            PlaceSearchSheet { selected in
                guard let index = searchingIndex,
                      options.indices.contains(index) else { return }
                options[index].title = selected.name
                if let url = selected.detailURL {
                    options[index].link = url
                }
            }
            .environment(appState)
        }
    }

    private var isValid: Bool {
        !question.isEmpty && options.filter({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count >= 2
    }

    // 여러 줄·공백이 섞인 붙여넣기에서 URL만 뽑아 필드를 정규화.
    private func handleLinkChange(index: Int, newValue: String) {
        guard options.indices.contains(index) else { return }
        if let extracted = URLExtractor.firstURL(in: newValue),
           extracted.absoluteString != newValue {
            options[index].link = extracted.absoluteString
        }
    }
}

#Preview {
    CreatePollView(onBack: {}, onCreated: { _ in })
}
