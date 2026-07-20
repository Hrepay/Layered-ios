import SwiftUI

struct PlaceCandidateDraft: Identifiable, Hashable {
    /// 기존 PollOption.id 또는 신규 UUID. 저장 시 voterIds 보존 키로 쓰임.
    let id: String
    var title: String
    var link: String

    init(id: String = UUID().uuidString, title: String = "", link: String = "") {
        self.id = id
        self.title = title
        self.link = link
    }

    static func from(option: PollOption) -> PlaceCandidateDraft {
        PlaceCandidateDraft(
            id: option.id,
            title: option.title,
            link: option.linkURL ?? ""
        )
    }
}

struct PlaceCandidatesEditor: View {
    @Binding var candidates: [PlaceCandidateDraft]
    var minCount: Int = 2
    var maxCount: Int = 4

    /// 장소 검색 시트가 채울 후보 인덱스. nil이면 시트 닫힘.
    @State private var searchingIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(candidates.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        AppTextField(
                            placeholder: "후보 \(index + 1) 장소명",
                            text: $candidates[index].title
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

                        if candidates.count > minCount {
                            Button {
                                Haptic.light()
                                _ = withAnimation(.spring(duration: 0.25)) {
                                    candidates.remove(at: index)
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
                        text: $candidates[index].link
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .onChange(of: candidates[index].link) { _, newValue in
                        normalizeLink(index: index, newValue: newValue)
                    }

                    if let url = URLExtractor.firstURL(in: candidates[index].link) {
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
                            .background(Capsule().fill(AppColors.primarySubtle))
                        }
                    }
                }
            }

            if candidates.count < maxCount {
                Button {
                    Haptic.light()
                    withAnimation(.spring(duration: 0.25)) {
                        candidates.append(PlaceCandidateDraft())
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AppColors.primary)
                        Text("후보 추가")
                            .foregroundStyle(.primary)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: Binding(
            get: { searchingIndex != nil },
            set: { if !$0 { searchingIndex = nil } }
        )) {
            PlaceSearchSheet { selected in
                guard let index = searchingIndex,
                      candidates.indices.contains(index) else { return }
                candidates[index].title = selected.name
                if let url = selected.detailURL {
                    candidates[index].link = url
                }
            }
        }
    }

    private func normalizeLink(index: Int, newValue: String) {
        guard candidates.indices.contains(index) else { return }
        if let extracted = URLExtractor.firstURL(in: newValue),
           extracted.absoluteString != newValue {
            candidates[index].link = extracted.absoluteString
        }
    }
}

extension PlaceCandidateDraft {
    /// 빈 제목 후보 제외하고 PollOption으로 변환. ID는 보존되어 voterIds 매칭에 사용됨.
    static func toPollOptions(_ drafts: [PlaceCandidateDraft]) -> [PollOption] {
        drafts.compactMap { draft in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let linkURL = URLExtractor.firstURL(in: draft.link)?.absoluteString
            return PollOption(
                id: draft.id,
                title: title,
                description: nil,
                imageURL: nil,
                linkURL: linkURL,
                voterIds: [],
                voteCount: 0
            )
        }
    }
}
