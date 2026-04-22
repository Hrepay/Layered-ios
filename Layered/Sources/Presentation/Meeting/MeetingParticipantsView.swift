import SwiftUI

struct MeetingParticipantsView: View {
    let onBack: () -> Void

    @Environment(AppState.self) private var appState: AppState

    @State private var expandedMember: Member?

    private var members: [Member] { appState.members }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "참여 인원 (\(members.count)명)", backAction: onBack)

            if members.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("참여 중인 인원이 없어요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(members) { member in
                        memberRow(member)
                            .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptic.light()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedMember = member
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .swipeBack(onBack: onBack)
        .overlay {
            if let member = expandedMember {
                ProfileImageViewer(member: member) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedMember = nil
                    }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func memberRow(_ member: Member) -> some View {
        HStack(spacing: 14) {
            AvatarView(name: member.name, size: 48, imageURL: member.profileImageURL)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if member.role == .admin {
                        BadgeView(text: "관리자", color: AppColors.primary)
                    }
                }

                Text("플래너 순서 \(member.rotationOrder + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct ProfileImageViewer: View {
    let member: Member
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptic.light()
                    onDismiss()
                }

            VStack(spacing: 18) {
                AvatarView(
                    name: member.name,
                    size: 240,
                    imageURL: member.profileImageURL
                )
                .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 6)

                Text(member.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .padding(40)
        }
    }
}
