import SwiftUI

enum ToastType {
    case success
    case error

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return AppColors.secondary
        case .error: return AppColors.danger
        }
    }
}

struct ToastView: View {
    let type: ToastType
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .foregroundStyle(type.color)
            Text(message)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(type: toast.type, message: toast.message)
                        .padding(.bottom, 120)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { self.toast = nil }
                            }
                        }
                }
            }
            .animation(.spring(duration: 0.3), value: toast != nil)
    }
}

struct ToastData: Equatable {
    let type: ToastType
    let message: String

    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.message == rhs.message
    }
}

extension View {
    func toast(_ data: Binding<ToastData?>) -> some View {
        modifier(ToastModifier(toast: data))
    }
}

#Preview {
    VStack {
        ToastView(type: .success, message: "저장되었습니다")
        ToastView(type: .error, message: "네트워크 오류가 발생했습니다")
    }
}
