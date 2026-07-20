import SwiftUI
import UIKit

enum AppColors {
    // Primary - Peach
    static let primary = adaptive(light: "FF9472", dark: "FFA584")
    static let primaryLight = adaptive(light: "FFB99A", dark: "B87A5F")
    static let primarySubtle = adaptive(light: "FFF0E8", dark: "3D2820")

    // Secondary - Olive
    static let secondary = adaptive(light: "8B9E6B", dark: "A3B683")
    static let secondarySubtle = adaptive(light: "EFF3E8", dark: "2A3020")

    // Info - Sky
    static let info = adaptive(light: "6BB5C9", dark: "8ECFDD")
    static let infoSubtle = adaptive(light: "E8F4F8", dark: "1A2E35")

    // Warning - Amber
    static let warning = adaptive(light: "F5A623", dark: "FFB850")
    static let warningSubtle = adaptive(light: "FFF4E0", dark: "3D2E10")

    // Danger - Soft Red (불참·삭제 등 부정 상태. 시스템 .red 대신 사용)
    static let danger = adaptive(light: "E05E5E", dark: "F08080")
    static let dangerSubtle = adaptive(light: "FBEAEA", dark: "3D1F1F")

    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
