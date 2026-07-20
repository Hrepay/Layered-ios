import SwiftUI

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "calendar.badge.clock",
            title: "매주 함께하는 시간",
            description: "매주 돌아가며 가족 모임을 계획하고\n소중한 시간을 만들어보세요"
        ),
        OnboardingPage(
            icon: "hand.thumbsup.fill",
            title: "함께 정하는 모임",
            description: "투표로 장소와 활동을 정하고\n모두가 만족하는 모임을 만들어요"
        ),
        OnboardingPage(
            icon: "photo.on.rectangle.angled",
            title: "추억을 기록하세요",
            description: "사진과 소감을 남기고\n우리 가족만의 히스토리를 쌓아가요"
        ),
    ]

    private var isLastPage: Bool {
        currentPage == pages.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // 건너뛰기
            HStack {
                Spacer()
                if !isLastPage {
                    Button("건너뛰기") {
                        Haptic.light()
                        onComplete()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 24)

            // 페이지 콘텐츠
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    VStack(spacing: 28) {
                        Spacer()

                        // 아이콘 배경 원
                        ZStack {
                            Circle()
                                .fill(AppColors.primarySubtle)
                                .frame(width: 140, height: 140)

                            Image(systemName: page.icon)
                                .font(.system(size: 56))
                                .foregroundStyle(AppColors.primary)
                        }

                        VStack(spacing: 12) {
                            Text(page.title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)

                            Text(page.description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }

                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                    .padding(.horizontal, 40)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            // 페이지 인디케이터
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? AppColors.primary : AppColors.primarySubtle)
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.bottom, 32)

            // 하단 버튼
            if isLastPage {
                Button(action: {
                    Haptic.medium()
                    onComplete()
                }) {
                    Text("시작하기")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            } else {
                Button(action: {
                    Haptic.medium()
                    withAnimation(.easeInOut) {
                        currentPage += 1
                    }
                }) {
                    Text("다음")
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
