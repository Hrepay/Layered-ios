import SwiftUI

// MARK: - 버튼 스타일
struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isEnabled ? AppColors.primary : Color(.systemGray4))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColors.primarySubtle)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - 카드 스타일
struct CardModifier: ViewModifier {
    var highlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(highlighted ? AppColors.primarySubtle : Color(.secondarySystemBackground))
            )
    }
}

struct TappableCardModifier: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1)
            .opacity(isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.15), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View {
        modifier(CardModifier(highlighted: highlighted))
    }

    func tappableCard() -> some View {
        modifier(TappableCardModifier())
    }
}

// MARK: - 뱃지
struct BadgeView: View {
    let text: String
    var color: Color = AppColors.primary

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - 아바타
struct AvatarView: View {
    let name: String
    var size: CGFloat = 44
    var imageURL: String? = nil

    private var fontSize: Font {
        if size <= 32 { return .caption }
        if size <= 44 { return .headline }
        return .title
    }

    var body: some View {
        if let imageURL, let url = URL(string: imageURL) {
            CachedAsyncImage(url: url)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            initialView
        }
    }

    private var initialView: some View {
        Circle()
            .fill(AppColors.primarySubtle)
            .frame(width: size, height: size)
            .overlay {
                Text(String(name.prefix(1)))
                    .font(fontSize)
                    .fontWeight(.medium)
            }
    }
}

// MARK: - 상단 네비게이션 바
struct NavBar: View {
    var title: String = ""
    var backAction: (() -> Void)? = nil
    var trailingText: String? = nil
    var trailingAction: (() -> Void)? = nil
    var trailingDisabled: Bool = false
    var trailingMenu: AnyView? = nil

    var body: some View {
        HStack {
            if let backAction {
                Button(action: backAction) {
                    Image(systemName: "chevron.left")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
            }

            Spacer()

            if !title.isEmpty {
                Text(title)
                    .font(.headline)
            }

            Spacer()

            if let trailingMenu {
                trailingMenu
                    .frame(width: 44, height: 44)
            } else if let trailingText, let trailingAction {
                Button(action: trailingAction) {
                    Text(trailingText)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(trailingDisabled ? .secondary : AppColors.primary)
                }
                .disabled(trailingDisabled)
                .frame(minWidth: 44)
                .frame(height: 44)
            } else if backAction != nil {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 입력 필드
struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? AppColors.primary : .clear, lineWidth: 1.5)
            )
            .focused($isFocused)
    }
}

// MARK: - 시간 포맷
/// "최근 수정 · OO · 5분 전" 같은 줄에서 쓰는 상대 시간 포맷.
/// 1분 미만은 "방금 전", 그 외는 한국어 RelativeDateTimeFormatter를 사용.
enum MeetingTimeFormat {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "방금 전" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - 햅틱
enum Haptic {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 별점(1~5)에 비례한 단계별 햅틱. 5점은 success 노티 햅틱까지 같이.
    static func starRating(_ rating: Int) {
        switch rating {
        case 1, 2: light()
        case 3: medium()
        case 4: heavy()
        case 5:
            heavy()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                success()
            }
        default: light()
        }
    }
}

// MARK: - Liquid Glass (iOS 26+)
/// iOS 26의 `glassEffect`를 우선 사용하고 그 이하 버전에서는 기존 `.card()`로 폴백.
/// 미니멀하게 highlighted 상태만 토글한다 — DESIGN_GUIDE의 컬러 사용 규칙 그대로.
extension View {
    @ViewBuilder
    func liquidGlassCard(highlighted: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self
                .padding(16)
                .glassEffect(
                    .regular.tint(highlighted ? AppColors.primarySubtle : Color.clear),
                    in: RoundedRectangle(cornerRadius: 20)
                )
        } else {
            self.card(highlighted: highlighted)
        }
    }
}

// MARK: - 스와이프로 뒤로가기 (fullScreenCover용)
struct SwipeBackModifier: ViewModifier {
    let onBack: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { value in
                                if value.translation.width > 60 {
                                    Haptic.light()
                                    onBack()
                                }
                            }
                    )
                    .ignoresSafeArea()
            }
    }
}

extension View {
    func swipeBack(onBack: @escaping () -> Void) -> some View {
        modifier(SwipeBackModifier(onBack: onBack))
    }

}
