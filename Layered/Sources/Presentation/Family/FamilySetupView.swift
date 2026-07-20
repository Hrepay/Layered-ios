import SwiftUI

enum FamilySetupStep {
    case select
    case create
    case profile(familyName: String)
    case joinProfile(Family)
    case inviteShare(String)
    case join
}

struct FamilySetupView: View {
    let onJoined: (Family) -> Void
    @Environment(AppState.self) private var appState: AppState
    @State private var step: FamilySetupStep = .select

    var body: some View {
        Group {
            switch step {
            case .select:
                familySelectView
            case .create:
                CreateFamilyView(onBack: {
                    step = .select
                }, onCreated: { familyName in
                    step = .profile(familyName: familyName)
                })
            case .profile(let familyName):
                ProfileSetupView(onBack: {
                    step = .create
                }, onComplete: { profileName, image in
                    createFamily(familyName: familyName, profileName: profileName, image: image)
                })
            case .inviteShare(let code):
                InviteCodeShareView(inviteCode: code, onDone: {
                    if let family = appState.currentFamily {
                        onJoined(family)
                    }
                })
            case .join:
                JoinFamilyView(onBack: {
                    step = .select
                }, onJoined: { family in
                    step = .joinProfile(family)
                })
                .environment(appState)
            case .joinProfile(let family):
                ProfileSetupView(onBack: {
                    step = .join
                }, onComplete: { profileName, image in
                    guard let userId = appState.currentUser?.id else { return }
                    appState.isLoading = true
                    Task {
                        do {
                            if let image {
                                try await appState.uploadProfileImage(image)
                                try await appState.updateProfile(name: profileName, profileImageURL: appState.currentUser?.profileImageURL)
                            } else {
                                // 이미지 미선택 → 기본 아바타(이니셜)로 리셋
                                try await appState.updateProfile(name: profileName, profileImageURL: nil)
                            }
                            // 프로필 완료 후 실제 가정 참여
                            try await appState.familyRepository.joinFamily(
                                familyId: family.id,
                                userId: userId,
                                userName: profileName,
                                inviteCode: family.inviteCode
                            )
                            // 이전에 이 가정에 있다가 나간 이력이 있으면 과거 콘텐츠의 "Guest" 이름을 현재 이름으로 복원
                            try? await appState.restoreUserContentName(familyId: family.id, userId: userId, newName: profileName)
                            appState.isLoading = false
                            onJoined(family)
                        } catch {
                            appState.error = AppError.from(error)
                            appState.isLoading = false
                        }
                    }
                })
            }
        }
        .animation(.easeInOut(duration: 0.25), value: String(describing: step))
    }

    private func createFamily(familyName: String, profileName: String, image: UIImage? = nil) {
        guard let userId = appState.currentUser?.id else { return }
        appState.isLoading = true
        Task {
            do {
                if let image {
                    // 프로필 사진 업로드 후 최신 URL로 이름과 함께 저장
                    try await appState.uploadProfileImage(image)
                    try await appState.updateProfile(name: profileName, profileImageURL: appState.currentUser?.profileImageURL)
                } else {
                    // 이미지 미선택 → 기본 아바타(이니셜)로 리셋
                    try await appState.updateProfile(name: profileName, profileImageURL: nil)
                }
                // 가정 생성
                let family = try await appState.familyRepository.createFamily(
                    name: familyName,
                    adminId: userId
                )
                appState.currentFamily = family
                // user.familyId 업데이트
                if var updatedUser = appState.currentUser {
                    updatedUser.familyId = family.id
                    try await appState.userRepository.updateUser(updatedUser)
                    appState.currentUser = updatedUser
                }
                await appState.loadHomeData()
                step = .inviteShare(family.inviteCode)
            } catch {
                appState.error = AppError.from(error)
            }
            appState.isLoading = false
        }
    }

    @State private var showLogoutAlert = false
    @State private var showDeleteAccountAlert = false

    private var familySelectView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "house.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.primary)

                Text("가정을 설정해주세요")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("가정을 새로 만들거나\n초대 코드로 기존 가정에 참여하세요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
                .frame(height: 48)

            VStack(spacing: 12) {
                Button(action: {
                    Haptic.light()
                    step = .create
                }) {
                    Text("새 가정 만들기")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: {
                    Haptic.light()
                    step = .join
                }) {
                    Text("초대 코드로 참여")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 24)

            Spacer()

            HStack(spacing: 24) {
                Button {
                    Haptic.light()
                    showLogoutAlert = true
                } label: {
                    Text("로그아웃")
                        .font(.subheadline)
                        .foregroundStyle(Color(.darkGray))
                }
                .buttonStyle(.plain)

                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                Button {
                    Haptic.light()
                    showDeleteAccountAlert = true
                } label: {
                    Text("계정 삭제")
                        .font(.subheadline)
                        .foregroundStyle(Color(.darkGray))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 32)
        }
        .alert("로그아웃", isPresented: $showLogoutAlert) {
            Button("취소", role: .cancel) {}
            Button("로그아웃", role: .destructive) {
                appState.signOut()
            }
        } message: {
            Text("로그아웃하시겠습니까?")
        }
        .alert("계정 삭제", isPresented: $showDeleteAccountAlert) {
            Button("취소", role: .cancel) {}
            Button("계속", role: .destructive) {
                Task {
                    do {
                        try await appState.deleteAccount()
                    } catch {
                        appState.error = AppError.from(error)
                    }
                }
            }
        } message: {
            Text("모든 데이터가 영구 삭제됩니다.\n본인 확인을 위해 이어서 Apple 로그인이 한 번 표시됩니다.")
        }
    }
}

#Preview {
    FamilySetupView(onJoined: { _ in })
}
