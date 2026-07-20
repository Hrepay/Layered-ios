import SwiftUI

// Xcode 프리뷰 전용 데모 — 릴리스 바이너리에서 제외
#if DEBUG

struct ColorPalettePreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("겹겹 컬러 팔레트")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 20)

                // Primary
                sectionTitle("Primary — Peach")
                HStack(spacing: 12) {
                    colorCard("Primary", AppColors.primary, "#FF9472")
                    colorCard("Light", AppColors.primaryLight, "#FFB99A")
                    colorCard("Subtle", AppColors.primarySubtle, "#FFF0E8", textDark: true)
                }

                // Secondary
                sectionTitle("Secondary — Olive")
                HStack(spacing: 12) {
                    colorCard("Olive", AppColors.secondary, "#8B9E6B")
                    Spacer()
                    Spacer()
                }

                // Info
                sectionTitle("Info — Sky")
                HStack(spacing: 12) {
                    colorCard("Sky", AppColors.info, "#6BB5C9")
                    Spacer()
                    Spacer()
                }

                // Status
                sectionTitle("Status")
                HStack(spacing: 12) {
                    colorCard("Warning", AppColors.warning, "#F5A623")
                    colorCard("Error", .red, "System")
                    Spacer()
                }

                // 사용 예시
                Divider()
                    .padding(.vertical, 8)

                sectionTitle("적용 예시")

                // 버튼 예시
                HStack(spacing: 12) {
                    Button(action: {}) {
                        Text("메인 버튼")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(AppColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: {}) {
                        Text("서브 버튼")
                            .font(.headline)
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(AppColors.primarySubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                // 카드 예시
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("확정")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColors.secondary)
                            .clipShape(Capsule())

                        Text("투표 진행 중")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColors.info)
                            .clipShape(Capsule())

                        Spacer()

                        Text("D-2")
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(AppColors.primary)
                        Text("한강공원")
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // 플래너 배너 예시
                HStack(spacing: 12) {
                    Circle()
                        .fill(AppColors.primarySubtle)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Text("상")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    Text("이번 주 플래너는 나!")
                        .font(.headline)
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppColors.primarySubtle)
                )

                // 다크 모드 후보
                Divider()
                    .padding(.vertical, 8)

                sectionTitle("다크 모드 후보 컬러")

                Text("다크 모드에서 채도 낮추고 밝기 살짝 줄인 버전")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    colorCard("Primary", Color(hex: "E8845F"), "#E8845F")
                    colorCard("Light", Color(hex: "D4896E"), "#D4896E")
                    colorCard("Subtle", Color(hex: "3D2A1F"), "#3D2A1F")
                }

                HStack(spacing: 12) {
                    colorCard("Olive", Color(hex: "7A8E5C"), "#7A8E5C")
                    colorCard("Sky", Color(hex: "5A9FB3"), "#5A9FB3")
                    colorCard("Warning", Color(hex: "D4901E"), "#D4901E")
                }

                // 다크 모드 비교 카드
                VStack(spacing: 8) {
                    Text("다크 모드 카드 미리보기")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        // 현재 피치 (다크 배경에서)
                        VStack(spacing: 8) {
                            Text("현재")
                                .font(.caption2)
                                .foregroundStyle(.white)
                            Circle()
                                .fill(AppColors.primary)
                                .frame(width: 40, height: 40)
                            Text("확정")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppColors.secondary)
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity)

                        // 다크 후보
                        VStack(spacing: 8) {
                            Text("다크 후보")
                                .font(.caption2)
                                .foregroundStyle(.white)
                            Circle()
                                .fill(Color(hex: "E8845F"))
                                .frame(width: 40, height: 40)
                            Text("확정")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "7A8E5C"))
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .background(Color(hex: "1C1C1E"))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorCard(_ name: String, _ color: Color, _ hex: String, textDark: Bool = false) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(height: 70)
                .overlay {
                    Text(name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(textDark ? .black : .white)
                }

            Text(hex)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("컬러 팔레트") {
    ColorPalettePreview()
}

#endif
