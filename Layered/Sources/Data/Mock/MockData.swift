import Foundation

enum MockData {
    // MARK: - Helpers

    private static let calendar = Calendar.current

    private static func daysFromNow(_ days: Int, hour: Int = 18, minute: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    // MARK: - Users
    static let currentUser = User(
        id: "user-001",
        name: "상환",
        profileImageURL: "https://picsum.photos/seed/hrepay-me/400/400",
        familyId: "family-001",
        createdAt: daysFromNow(-120),
        agreedTermsAt: daysFromNow(-120),
        agreedTermsVersion: "1.0",
        marketingConsent: true
    )

    // MARK: - Family
    static let family = Family(
        id: "family-001",
        name: "황씨네",
        inviteCode: "HRPY26",
        inviteCodeExpiresAt: Date().addingTimeInterval(1500),
        adminId: "user-001",
        memberCount: 4,
        currentPlannerIndex: 0,
        rotationDay: 1,
        rotationMode: "auto",
        createdAt: daysFromNow(-180)
    )

    // MARK: - Members
    static let members: [Member] = [
        Member(
            id: "user-001",
            name: "상환",
            profileImageURL: "https://picsum.photos/seed/hrepay-me/400/400",
            role: .admin,
            rotationOrder: 0,
            joinedAt: daysFromNow(-180)
        ),
        Member(
            id: "user-002",
            name: "엄마",
            profileImageURL: "https://picsum.photos/seed/hrepay-mom/400/400",
            role: .member,
            rotationOrder: 1,
            joinedAt: daysFromNow(-180)
        ),
        Member(
            id: "user-003",
            name: "아빠",
            profileImageURL: "https://picsum.photos/seed/hrepay-dad/400/400",
            role: .member,
            rotationOrder: 2,
            joinedAt: daysFromNow(-180)
        ),
        Member(
            id: "user-004",
            name: "누나",
            profileImageURL: "https://picsum.photos/seed/hrepay-sis/400/400",
            role: .member,
            rotationOrder: 3,
            joinedAt: daysFromNow(-150)
        ),
    ]

    // MARK: - Meetings
    static let meetings: [Meeting] = [
        // 이번 주 예정 모임
        Meeting(
            id: "meeting-upcoming",
            plannerId: "user-001",
            plannerName: "상환",
            meetingDate: daysFromNow(3, hour: 17, minute: 30),
            place: "한강공원 뚝섬지구",
            placeLatitude: 37.5316,
            placeLongitude: 127.0688,
            placeURL: "https://map.naver.com/v5/entry/place/11557509",
            activity: "피크닉, 산책, 자전거",
            status: .confirmed,
            hasPoll: true,
            createdAt: daysFromNow(-2),
            updatedAt: daysFromNow(-1)
        ),
        // 지난 모임 1
        Meeting(
            id: "meeting-past-1",
            plannerId: "user-002",
            plannerName: "엄마",
            meetingDate: daysFromNow(-5, hour: 16, minute: 0),
            place: "한강공원 반포지구",
            placeLatitude: 37.5110,
            placeLongitude: 126.9964,
            placeURL: nil,
            activity: "피크닉, 산책",
            status: .completed,
            hasPoll: false,
            createdAt: daysFromNow(-12),
            updatedAt: daysFromNow(-5)
        ),
        // 지난 모임 2
        Meeting(
            id: "meeting-past-2",
            plannerId: "user-003",
            plannerName: "아빠",
            meetingDate: daysFromNow(-12, hour: 10, minute: 0),
            place: "북한산 둘레길",
            placeLatitude: 37.6588,
            placeLongitude: 126.9779,
            placeURL: nil,
            activity: "산책, 운동",
            status: .completed,
            hasPoll: false,
            createdAt: daysFromNow(-20),
            updatedAt: daysFromNow(-12)
        ),
        // 지난 모임 3
        Meeting(
            id: "meeting-past-3",
            plannerId: "user-004",
            plannerName: "누나",
            meetingDate: daysFromNow(-19, hour: 14, minute: 0),
            place: "연남동 카페",
            placeLatitude: 37.5623,
            placeLongitude: 126.9259,
            placeURL: nil,
            activity: "카페, 문화생활",
            status: .completed,
            hasPoll: false,
            createdAt: daysFromNow(-25),
            updatedAt: daysFromNow(-19)
        ),
    ]

    // MARK: - Poll (이번 주 예정 모임용)
    static let poll = Poll(
        id: "poll-001",
        question: "뭐 하고 놀까요?",
        isAnonymous: false,
        allowMultiple: true,
        options: [
            PollOption(
                id: "opt-1",
                title: "피크닉 + 자전거",
                description: nil,
                imageURL: nil,
                linkURL: nil,
                voterIds: ["user-001", "user-002"],
                voteCount: 2
            ),
            PollOption(
                id: "opt-2",
                title: "배드민턴",
                description: nil,
                imageURL: nil,
                linkURL: nil,
                voterIds: ["user-003"],
                voteCount: 1
            ),
            PollOption(
                id: "opt-3",
                title: "강변 산책만",
                description: nil,
                imageURL: nil,
                linkURL: nil,
                voterIds: ["user-002"],
                voteCount: 1
            ),
        ],
        createdAt: daysFromNow(-1)
    )

    // MARK: - Records
    /// RecordDetailView가 단일 배열을 받는 구조이므로 가장 최근 지난 모임(`meeting-past-1` = 한강공원 반포지구) 기록만 반환.
    static let records: [MeetingRecord] = [
        MeetingRecord(
            id: "record-001",
            memberId: "user-001",
            memberName: "상환",
            photos: [
                "asset://MockHangang1",
                "asset://MockHangang2",
            ],
            comment: "오랜만에 한강 와서 자전거 타니까 진짜 재밌네 ㅋㅋ 다음엔 형도 꼭 데려오자",
            rating: 5,
            createdAt: daysFromNow(-5, hour: 21),
            updatedAt: daysFromNow(-5, hour: 21)
        ),
        MeetingRecord(
            id: "record-002",
            memberId: "user-002",
            memberName: "엄마",
            photos: [
                "asset://MockMomDog",
            ],
            comment: "뿌꾸랑 코코 너무 좋아하더라 ㅎㅎ 다음에 또 오자~",
            rating: 5,
            createdAt: daysFromNow(-5, hour: 20, minute: 30),
            updatedAt: daysFromNow(-5, hour: 20, minute: 30)
        ),
        MeetingRecord(
            id: "record-003",
            memberId: "user-003",
            memberName: "아빠",
            photos: [],
            comment: "자전거 타기 좋은 날씨. 다음에도 한강으로.",
            rating: 4,
            createdAt: daysFromNow(-4, hour: 20),
            updatedAt: daysFromNow(-4, hour: 20)
        ),
    ]

    // MARK: - Notes (한 겹) — 모임 없이 그냥 남긴 가벼운 메모
    static let notes: [Note] = [
        Note(
            id: "note-001",
            authorId: "user-003",
            authorName: "아빠",
            text: "이번 주는 각자 바빠서 못 모였지만, 아빠가 김치찌개 끓여줌 🍲",
            photoURL: nil,
            date: daysFromNow(-9, hour: 19),
            createdAt: daysFromNow(-9, hour: 19),
            updatedAt: daysFromNow(-9, hour: 19)
        ),
        Note(
            id: "note-002",
            authorId: "user-001",
            authorName: "상환",
            text: "다 같이 저녁 먹으면서 예전 앨범 구경함. 별 거 아닌데 좋았다.",
            photoURL: "https://picsum.photos/seed/note002/800/800",
            date: daysFromNow(-16, hour: 21),
            createdAt: daysFromNow(-16, hour: 21),
            updatedAt: daysFromNow(-16, hour: 21)
        ),
    ]
}
