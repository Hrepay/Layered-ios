import SwiftUI

/// 홈 헤더 아래 가로 스크롤 멤버 strip.
/// - 이번 주 활동이 있으면(이번 주 모임에 .going) primary 컬러 링으로 강조
/// - 본인은 항상 맨 앞 + "나" 라벨
/// - 탭하면 멤버 활동 시트
struct MemberStoriesStrip: View {
    let members: [Member]
    let currentUserId: String
    let meetings: [Meeting]
    var onSelect: (Member) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 🔥 의미를 한 줄로 설명. 이번 주 참석자가 한 명도 없으면 안내 톤을 다르게.
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.primary)
                Text(stripCaption)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(orderedMembers) { member in
                        Button {
                            Haptic.light()
                            onSelect(member)
                        } label: {
                            memberCell(member)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
        }
    }

    /// 캡션 텍스트 — 이번 주 참석자 수에 따라 톤 변경.
    /// 0명: 응답 유도 톤 / 1명+: 누가 참석하는지 한눈에.
    private var stripCaption: String {
        let activeCount = orderedMembers.filter { isActiveThisWeek($0) }.count
        if activeCount == 0 {
            return "이번 주 모임 참석 응답이 아직 없어요"
        }
        return "이번 주 모임 참석자 \(activeCount)명"
    }

    /// 본인 먼저, 그다음 rotationOrder 기준.
    private var orderedMembers: [Member] {
        let sorted = members.sorted { $0.rotationOrder < $1.rotationOrder }
        guard let me = sorted.first(where: { $0.id == currentUserId }) else { return sorted }
        return [me] + sorted.filter { $0.id != currentUserId }
    }

    @ViewBuilder
    private func memberCell(_ member: Member) -> some View {
        let active = isActiveThisWeek(member)
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(active ? AppColors.primary : Color(.systemGray5), lineWidth: active ? 2.5 : 1.5)
                    .frame(width: 64, height: 64)
                AvatarView(name: member.name, size: 54, imageURL: member.profileImageURL)
                if active {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(AppColors.primary))
                        .offset(x: 22, y: 22)
                }
            }
            Text(member.id == currentUserId ? "나" : member.name)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 72)
    }

    /// 이번 주 (월~일 ISO 8601) 모임 중 이 멤버가 .going인 게 있는지.
    private func isActiveThisWeek(_ member: Member) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let now = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return false }
        return meetings.contains { meeting in
            weekInterval.contains(meeting.meetingDate)
                && meeting.attendance[member.id] == .going
        }
    }
}

// MARK: - 멤버 활동 시트

/// 멤버 탭 시 띄우는 시트. 이미 로드된 데이터만으로 즉시 표시 가능한 항목 위주.
struct MemberActivitySheet: View {
    let member: Member
    let meetings: [Meeting]
    let allMembers: [Member]
    let currentUserId: String
    let onClose: () -> Void

    @Environment(AppState.self) private var appState: AppState

    @State private var selectedMeeting: Meeting?
    @State private var recordsLoading = true
    @State private var recordCount = 0
    @State private var avgRating: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    statsRow
                    if !thisWeekMeetings.isEmpty {
                        thisWeekSection
                    }
                    recentMeetingsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { onClose() }
                }
            }
            .task { await loadMemberRecords() }
        }
    }

    /// 모든 모임을 순회하며 이 멤버가 작성한 기록의 개수·별점을 집계.
    /// AppState.checkMyRecords와 같은 패턴 — 무겁지만 시트 1회 열림이라 허용.
    private func loadMemberRecords() async {
        var count = 0
        var ratings: [Int] = []
        for meeting in meetings {
            if let records = try? await appState.getRecords(meetingId: meeting.id) {
                for record in records where record.memberId == member.id {
                    count += 1
                    ratings.append(record.rating)
                }
            }
        }
        recordCount = count
        avgRating = ratings.isEmpty ? 0 : Double(ratings.reduce(0, +)) / Double(ratings.count)
        recordsLoading = false
    }

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(name: member.name, size: 88, imageURL: member.profileImageURL)
            Text(member.id == currentUserId ? "\(member.name) (나)" : member.name)
                .font(.title2)
                .fontWeight(.bold)
            HStack(spacing: 6) {
                if member.role == .admin {
                    BadgeView(text: "관리자", color: AppColors.primary)
                }
                Text("\(member.rotationOrder + 1)번째 플래너 순서")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(
                label: "함께한\n모임",
                value: "\(totalAttendCount)회",
                icon: "checkmark.circle.fill",
                tint: AppColors.secondary
            )
            statCard(
                label: "참석률",
                value: attendanceRateLabel,
                icon: "chart.pie.fill",
                tint: AppColors.info
            )
            statCard(
                label: "평균 별점",
                value: avgRatingLabel,
                icon: "star.fill",
                tint: AppColors.warning
            )
        }
    }

    private func statCard(label: String, value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .card()
    }

    @ViewBuilder
    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("이번 주")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            ForEach(thisWeekMeetings) { meeting in
                miniMeetingRow(meeting)
            }
        }
    }

    private var recentMeetingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최근 활동")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            if recentMeetings.isEmpty {
                Text("최근 참여한 모임이 없어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(recentMeetings) { meeting in
                    miniMeetingRow(meeting)
                }
            }
        }
    }

    private func miniMeetingRow(_ meeting: Meeting) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rowIcon(for: meeting))
                .font(.caption)
                .foregroundStyle(rowIconColor(for: meeting))
                .frame(width: 28, height: 28)
                .background(Circle().fill(rowIconColor(for: meeting).opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayPlace)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(rowSubtitle(for: meeting))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card()
    }

    // MARK: - Computed

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    private var thisWeekMeetings: [Meeting] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return meetings
            .filter { interval.contains($0.meetingDate) && $0.attendance[member.id] == .going }
    }

    /// 누적 참석 — 이 멤버가 .going으로 응답한 모든 모임 수 (지난·다가오는·플래너 포함).
    private var totalAttendCount: Int {
        meetings.filter { $0.attendance[member.id] == .going }.count
    }

    /// 참석률 — (가족 합류 후) 응답 가능한 모임 중 .going 비율.
    /// 분모: joinedAt 이후 status != .cancelled 인 모임 수.
    /// 가족 합류 후 모임이 0개면 "—" 반환.
    private var attendanceRateLabel: String {
        let eligible = meetings.filter {
            $0.meetingDate >= member.joinedAt && $0.status != .cancelled
        }
        guard !eligible.isEmpty else { return "—" }
        let going = eligible.filter { $0.attendance[member.id] == .going }.count
        let pct = Int(Double(going) / Double(eligible.count) * 100)
        return "\(pct)%"
    }

    /// 평균 별점 — 비동기 fetch 결과. 로딩 중에는 "…", 기록 없으면 "—".
    private var avgRatingLabel: String {
        if recordsLoading { return "…" }
        if recordCount == 0 { return "—" }
        return String(format: "%.1f", avgRating)
    }

    private var recentMeetings: [Meeting] {
        let attended = meetings
            .filter {
                $0.attendance[member.id] == .going || $0.plannerId == member.id
            }
            .prefix(5)
        return Array(attended)
    }

    private func rowIcon(for meeting: Meeting) -> String {
        if meeting.plannerId == member.id { return "person.fill" }
        if meeting.attendance[member.id] == .going { return "checkmark" }
        return "questionmark"
    }

    private func rowIconColor(for meeting: Meeting) -> Color {
        if meeting.plannerId == member.id { return AppColors.primary }
        if meeting.attendance[member.id] == .going { return AppColors.secondary }
        return AppColors.warning
    }

    private func rowSubtitle(for meeting: Meeting) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E)"
        let date = f.string(from: meeting.meetingDate)
        if meeting.plannerId == member.id {
            return "\(date) · 주최"
        }
        return date
    }
}

#Preview("Strip") {
    MemberStoriesStrip(
        members: MockData.members,
        currentUserId: MockData.currentUser.id,
        meetings: MockData.meetings,
        onSelect: { _ in }
    )
    .padding(.vertical, 20)
}

#Preview("Activity Sheet") {
    MemberActivitySheet(
        member: MockData.members[0],
        meetings: MockData.meetings,
        allMembers: MockData.members,
        currentUserId: MockData.currentUser.id,
        onClose: {}
    )
}
