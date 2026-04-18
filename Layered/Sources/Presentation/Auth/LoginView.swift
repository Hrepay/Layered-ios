import SwiftUI

struct LoginView: View {
    let onSignIn: (_ marketingConsent: Bool) -> Void
    var onDebugSignIn: ((String, String, Bool) -> Void)?

    @State private var appeared = false
    @State private var showAgreement = false
    @State private var pendingAction: PendingLoginAction?
    @Environment(\.colorScheme) private var colorScheme

    private enum PendingLoginAction {
        case apple
        case debug(String, String)
    }

    #if DEBUG
    // Xcode Scheme → Run → Arguments → Environment Variables 에서 DEBUG_EMAIL, DEBUG_PASSWORD 설정 시에만 노출
    private var debugCredentials: (String, String)? {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["DEBUG_EMAIL"], !email.isEmpty,
              let password = env["DEBUG_PASSWORD"], !password.isEmpty else { return nil }
        return (email, password)
    }
    #endif

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 로고 섹션
            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)

                Text("겹겹")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)

                Text("가족과 함께하는 따뜻한 시간을 만들어요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            Spacer()

            // 하단 로그인 영역
            VStack(spacing: 16) {
                // Apple 로그인 버튼
                Button(action: {
                    Haptic.medium()
                    pendingAction = .apple
                    showAgreement = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                            .font(.title3)
                        Text("Apple로 로그인")
                            .font(.headline)
                    }
                    // Apple HIG: 밝은 배경엔 검정 버튼, 어두운 배경엔 흰 버튼.
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                #if DEBUG
                if let (debugEmail, debugPassword) = debugCredentials {
                    Button(action: {
                        Haptic.light()
                        pendingAction = .debug(debugEmail, debugPassword)
                        showAgreement = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill")
                                .font(.title3)
                            Text("테스트 계정 로그인")
                                .font(.headline)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                #endif

                // 약관 안내
                Text("로그인 단계에서 이용약관 및 개인정보 처리방침 동의 절차를 진행합니다")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showAgreement, onDismiss: {
            // 스와이프로 내리거나 X 눌러 닫을 때도 안전하게 초기화
            pendingAction = nil
        }) {
            TermsAgreementSheet(
                onConfirm: { marketingConsent in
                    let action = pendingAction
                    showAgreement = false
                    switch action {
                    case .apple:
                        onSignIn(marketingConsent)
                    case .debug(let email, let password):
                        onDebugSignIn?(email, password, marketingConsent)
                    case .none:
                        break
                    }
                },
                onCancel: {
                    showAgreement = false
                }
            )
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
        }
    }
}

#Preview {
    LoginView(onSignIn: { _ in })
}
