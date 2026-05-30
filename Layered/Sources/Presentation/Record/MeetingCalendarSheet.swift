import SwiftUI

/// 모임이 있었던 날을 도트로 표시하는 귀여운 월별 달력 모달.
/// - 월 좌우 이동 가능 (chevron 버튼 + swipe 제스처)
/// - 모임 있는 날: 피치 톤 채움 + 흰 글씨, 동시에 하단 도트
/// - 오늘: 외곽 링
/// - 미래 달은 회색 처리
struct MeetingCalendarSheet: View {
    let meetings: [Meeting]
    let onClose: () -> Void

    @State private var anchorDate: Date = Date()

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ko_KR")
        c.firstWeekday = 2 // 월요일 시작
        return c
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    monthHeader

                    // 요일 헤더
                    HStack(spacing: 0) {
                        ForEach(["월", "화", "수", "목", "금", "토", "일"], id: \.self) { day in
                            Text(day)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(day == "일" ? AppColors.primary : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // 날짜 그리드
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                        ForEach(daysInGrid, id: \.id) { cell in
                            dayCell(cell)
                        }
                    }

                    legend
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("모임 캘린더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { onClose() }
                }
            }
        }
    }

    // MARK: - 월 헤더 (좌우 이동)
    private var monthHeader: some View {
        HStack {
            Button {
                Haptic.light()
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppColors.primarySubtle))
            }

            Spacer()

            Text(monthLabel)
                .font(.title3)
                .fontWeight(.bold)

            Spacer()

            Button {
                Haptic.light()
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppColors.primarySubtle))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 셀
    @ViewBuilder
    private func dayCell(_ cell: DayCell) -> some View {
        let hasMeet = hasMeeting(on: cell.date)
        let isToday = calendar.isDateInToday(cell.date)
        let isCurrentMonth = cell.isCurrentMonth

        ZStack {
            // 모임 있는 날: 피치 채움 (귀여운 둥근 사각형)
            if hasMeet && isCurrentMonth {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.primary)
            } else if isToday && isCurrentMonth {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.primary, lineWidth: 2)
            }

            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: cell.date))")
                    .font(.subheadline)
                    .fontWeight(hasMeet ? .bold : .medium)
                    .foregroundStyle(cellTextColor(hasMeet: hasMeet, isCurrentMonth: isCurrentMonth, isToday: isToday))

                // 모임 있는 날 하단 작은 도트(보조 시각화)
                if hasMeet && isCurrentMonth {
                    Circle()
                        .fill(.white)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(height: 44)
    }

    private func cellTextColor(hasMeet: Bool, isCurrentMonth: Bool, isToday: Bool) -> Color {
        if !isCurrentMonth { return Color(.systemGray3) }
        if hasMeet { return .white }
        if isToday { return AppColors.primary }
        return .primary
    }

    // MARK: - 범례
    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(AppColors.primary)
                    .frame(width: 16, height: 16)
                Text("모임 있던 날")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(AppColors.primary, lineWidth: 2)
                    .frame(width: 16, height: 16)
                Text("오늘")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - 계산

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월"
        return f.string(from: anchorDate)
    }

    private func shiftMonth(_ delta: Int) {
        if let new = calendar.date(byAdding: .month, value: delta, to: anchorDate) {
            withAnimation(.easeInOut(duration: 0.2)) {
                anchorDate = new
            }
        }
    }

    /// 그리드에 들어가는 셀들 — 이번 달 첫 주의 빈 칸(이전 달 일부)부터 마지막 주의 빈 칸까지 포함.
    private var daysInGrid: [DayCell] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: anchorDate) else {
            return []
        }
        let monthStart = monthInterval.start
        let monthEnd = monthInterval.end

        // 그리드 시작: 이번 달 첫째 날이 속한 주의 월요일
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: monthStart) else {
            return []
        }
        let gridStart = weekInterval.start

        var cells: [DayCell] = []
        var date = gridStart
        // 6주 × 7일 = 42 셀 최대
        for _ in 0..<42 {
            let isCurrent = date >= monthStart && date < monthEnd
            cells.append(DayCell(date: date, isCurrentMonth: isCurrent))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
            // 다음 달까지 다 채웠고 한 주가 끝났으면 stop
            if !isCurrent && date >= monthEnd && calendar.component(.weekday, from: date) == calendar.firstWeekday {
                break
            }
        }
        return cells
    }

    private func hasMeeting(on date: Date) -> Bool {
        meetings.contains { meeting in
            meeting.status != .cancelled
                && calendar.isDate(meeting.meetingDate, inSameDayAs: date)
        }
    }

    private struct DayCell: Identifiable {
        let date: Date
        let isCurrentMonth: Bool
        var id: TimeInterval { date.timeIntervalSince1970 }
    }
}

#Preview {
    MeetingCalendarSheet(meetings: MockData.meetings, onClose: {})
}
