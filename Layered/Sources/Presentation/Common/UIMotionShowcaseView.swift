import SwiftUI

/// 이번에 추가된 4가지 UI 모션을 BEFORE / AFTER로 나란히 비교해서 보는 데모 화면.
/// - 별점 단계별 햅틱
/// - 투표 결과 막대 reveal
/// - 플래너 바통 터치 트랜지션
/// - Liquid Glass 카드 (iOS 26+)
///
/// 사용법: Xcode에서 이 파일을 열고 우측 프리뷰 캔버스를 활성화(⌥⌘P)한 뒤
/// 각 섹션의 "▶ 재생" 버튼을 눌러서 좌우 비교.
struct UIMotionShowcaseView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                StarHapticSection()
                Divider()
                PollRevealSection()
                Divider()
                PlannerBatonSection()
                Divider()
                LiquidGlassSection()
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UI 모션 비교")
                .font(.largeTitle)
                .bold()
            Text("BEFORE ↔ AFTER 로 나란히 확인")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 섹션 공통

private struct SectionHeader: View {
    let title: String
    let desc: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3)
                .bold()
            Text(desc)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ColumnLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
    }
}

// MARK: - 1. 별점 단계별 햅틱

private struct StarHapticSection: View {
    @State private var beforeRating = 0
    @State private var afterRating = 0
    @State private var animatedBefore: Int? = nil
    @State private var animatedAfter: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "1. 별점 단계별 햅틱",
                desc: "전에는 모든 별이 같은 light 햅틱. 이제 별 개수가 늘어날수록 점점 묵직해지고 5★은 success 알림까지."
            )

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    ColumnLabel(text: "BEFORE")
                    stars(rating: $beforeRating, animated: $animatedBefore, before: true)
                    Text("전부 동일한 light 톡")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ColumnLabel(text: "AFTER")
                    stars(rating: $afterRating, animated: $animatedAfter, before: false)
                    Text(afterHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var afterHint: String {
        switch afterRating {
        case 0: return "탭해서 단계 차이를 느껴봐"
        case 1, 2: return "light · 가벼운 톡"
        case 3: return "medium · 무게감 있는 톡"
        case 4: return "heavy · 묵직한 톡"
        case 5: return "heavy + success ✨"
        default: return ""
        }
    }

    @ViewBuilder
    private func stars(rating: Binding<Int>, animated: Binding<Int?>, before: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    if before {
                        Haptic.light()
                    } else {
                        Haptic.starRating(star)
                    }
                    withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
                        rating.wrappedValue = star
                        animated.wrappedValue = star
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        animated.wrappedValue = nil
                    }
                } label: {
                    Image(systemName: star <= rating.wrappedValue ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(
                            star <= rating.wrappedValue ? AppColors.warning : Color(.systemGray4)
                        )
                        .scaleEffect(animated.wrappedValue == star ? 1.3 : 1.0)
                        .animation(.spring(duration: 0.3, bounce: 0.5), value: animated.wrappedValue)
                }
            }
        }
    }
}

// MARK: - 2. 투표 결과 막대 reveal

private struct PollRevealSection: View {
    @State private var beforeKey = UUID()
    @State private var afterKey = UUID()

    private let options: [(title: String, count: Int, isWinner: Bool)] = [
        ("한강공원", 4, true),
        ("올림픽공원", 2, false),
        ("남산", 1, false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "2. 투표 결과 막대 reveal",
                desc: "전에는 화면 들어가자마자 결과가 그대로 보임. 이제 카드가 stagger로 등장하고 막대가 0→실제값으로 차오름. 1등은 더 늦게 + 강조."
            )

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    ColumnLabel(text: "BEFORE")
                    BeforePollChart(options: options)
                        .id(beforeKey)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ColumnLabel(text: "AFTER")
                    AfterPollChart(options: options)
                        .id(afterKey)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                beforeKey = UUID()
                afterKey = UUID()
            } label: {
                Label("재생", systemImage: "play.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct BeforePollChart: View {
    let options: [(title: String, count: Int, isWinner: Bool)]
    private var total: Int { options.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                miniBar(title: o.title, count: o.count, isWinner: o.isWinner, fraction: CGFloat(o.count) / CGFloat(max(total, 1)))
            }
        }
    }

    @ViewBuilder
    private func miniBar(title: String, count: Int, isWinner: Bool, fraction: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(isWinner ? .bold : .regular)
                Spacer()
                Text("\(count)표")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isWinner ? AppColors.primary : Color(.systemGray3))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct AfterPollChart: View {
    let options: [(title: String, count: Int, isWinner: Bool)]
    @State private var revealedIndexes: Set<Int> = []
    @State private var progress: CGFloat = 0

    private var total: Int { options.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                let revealed = revealedIndexes.contains(i)
                let animCount = Int((Double(o.count) * Double(progress)).rounded())
                let frac = CGFloat(o.count) / CGFloat(max(total, 1)) * progress

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(o.title)
                            .font(.caption)
                            .fontWeight(o.isWinner ? .bold : .regular)
                        Spacer()
                        Text("\(animCount)표")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(o.isWinner ? AppColors.primary : Color(.systemGray3))
                                .frame(width: geo.size.width * frac)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .scaleEffect(o.isWinner && revealed ? 1.04 : 1.0)
                .shadow(color: o.isWinner && revealed ? AppColors.primary.opacity(0.3) : .clear,
                        radius: o.isWinner && revealed ? 8 : 0, y: 3)
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 10)
                .animation(.spring(duration: 0.5, bounce: 0.3), value: revealed)
            }
        }
        .onAppear {
            revealedIndexes.removeAll()
            progress = 0
            for i in options.indices {
                let extra = options[i].isWinner ? 0.2 : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1 + extra) {
                    withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                        _ = revealedIndexes.insert(i)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(duration: 0.8, bounce: 0.2)) {
                    progress = 1
                }
            }
        }
    }
}

// MARK: - 3. 플래너 바통 터치

private struct PlannerBatonSection: View {
    private let names = ["엄마", "아빠", "지호", "수민"]
    @State private var beforeIndex = 0
    @State private var afterIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "3. 플래너 바통 터치",
                desc: "전에는 플래너가 바뀌면 아바타·이름이 즉시 교체. 이제 이전 플래너가 ←왼쪽으로 빠지고 다음 플래너가 →오른쪽에서 슬라이드해서 들어옴."
            )

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    ColumnLabel(text: "BEFORE")
                    plannerRow(name: names[beforeIndex])
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(spacing: 8) {
                    ColumnLabel(text: "AFTER")
                    HStack(spacing: 10) {
                        AvatarView(name: names[afterIndex], size: 44)
                            .id("avatar-\(afterIndex)")
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))

                        Text(names[afterIndex])
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .id("name-\(afterIndex)")
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .padding(.horizontal, 10)
                    .background(AppColors.primarySubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .clipped()
                    .animation(.spring(duration: 0.55, bounce: 0.35), value: afterIndex)
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                Haptic.medium()
                beforeIndex = (beforeIndex + 1) % names.count
                afterIndex = (afterIndex + 1) % names.count
            } label: {
                Label("다음 플래너로 바꿔보기", systemImage: "arrow.right.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func plannerRow(name: String) -> some View {
        HStack(spacing: 10) {
            AvatarView(name: name, size: 44)
            Text(name)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .padding(.horizontal, 10)
        .background(AppColors.primarySubtle)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 4. Liquid Glass

private struct LiquidGlassSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "4. Liquid Glass (iOS 26+)",
                desc: "전에는 단색 채움. iOS 26 이상에서는 카드 뒤가 살짝 흐릿한 유리 머티리얼 + 색조 틴트 (이하 버전은 자동으로 기존 디자인 유지)."
            )

            // 알록달록 배경 위에 두 카드를 띄워서 유리 효과 비교
            ZStack {
                LinearGradient(
                    colors: [AppColors.info, AppColors.primary, AppColors.warning],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                HStack(spacing: 10) {
                    // BEFORE
                    VStack(spacing: 6) {
                        ColumnLabel(text: "BEFORE")
                        VStack(spacing: 4) {
                            Text("D-3")
                                .font(.title)
                                .bold()
                            Text("다음 모임까지")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(AppColors.primaryLight)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    // AFTER
                    VStack(spacing: 6) {
                        ColumnLabel(text: "AFTER")
                        glassDDayCard
                    }
                }
                .padding(20)
            }

            Text("iOS 26 미만에서는 BEFORE와 AFTER가 동일하게 보임 (자동 폴백).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var glassDDayCard: some View {
        let content = VStack(spacing: 4) {
            Text("D-3")
                .font(.title)
                .bold()
            Text("다음 모임까지")
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)

        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.tint(AppColors.primaryLight),
                in: RoundedRectangle(cornerRadius: 16)
            )
        } else {
            content.background(AppColors.primaryLight)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview("UI 모션 비교") {
    UIMotionShowcaseView()
}
