import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseMessaging
import FirebaseFirestore

enum AuthState: Equatable {
    case splash
    case onboarding
    case login
    case familySetup
    case home
}

// 관측 상태(isLoading·error·meetings 등)를 항상 메인 스레드에서만 변경하도록 클래스 전체를 격리.
@MainActor
@Observable
final class AppState {
    // MARK: - Mock 모드 스위치 (스크린샷·데모용)
    #if DEBUG
    /// true로 바꾸고 빌드하면 Firebase 대신 MockData로 홈부터 바로 진입. App Store 스크린샷 찍을 때 사용.
    nonisolated(unsafe) static var useMockForScreenshots = false
    #endif

    private var shouldUseMock: Bool {
        #if DEBUG
        return Self.useMockForScreenshots
        #else
        return false
        #endif
    }

    var authState: AuthState = .splash
    var currentUser: User?
    var currentFamily: Family?
    var members: [Member] = []
    var meetings: [Meeting] = []
    /// 모임과 별개로 남긴 가벼운 메모("한 겹"). date desc 정렬로 유지.
    var notes: [Note] = []
    var myRecordedMeetingIds: Set<String> = []
    var averageRating: Double = 0
    var consecutiveWeeks: Int = 0
    var isLoading = false
    var error: AppError?
    /// 푸시 탭으로 들어온 deep-link. 소비자(HomeView/MeetingDetailView)가 처리 후 nil로 비움.
    var pendingDeepLink: DeepLink?

    // @Observable은 lazy를 지원하지 않으므로 수동 캐싱 — 관측 대상에서 제외
    @ObservationIgnored private var _authRepository: AuthRepositoryProtocol?
    @ObservationIgnored private var _userRepository: UserRepositoryProtocol?
    @ObservationIgnored private var _familyRepository: FamilyRepositoryProtocol?
    @ObservationIgnored private var _memberRepository: MemberRepositoryProtocol?
    @ObservationIgnored private var _meetingRepository: MeetingRepositoryProtocol?
    @ObservationIgnored private var _pollRepository: PollRepositoryProtocol?
    @ObservationIgnored private var _recordRepository: RecordRepositoryProtocol?
    @ObservationIgnored private var _noteRepository: NoteRepositoryProtocol?
    @ObservationIgnored private var _storageRepository: StorageRepositoryProtocol?

    private var authRepository: AuthRepositoryProtocol {
        if _authRepository == nil {
            _authRepository = shouldUseMock ? MockAuthRepository() : FirebaseAuthRepository()
        }
        return _authRepository!
    }
    var userRepository: UserRepositoryProtocol {
        if _userRepository == nil {
            _userRepository = shouldUseMock ? MockUserRepository() : FirebaseUserRepository()
        }
        return _userRepository!
    }
    var familyRepository: FamilyRepositoryProtocol {
        if _familyRepository == nil {
            _familyRepository = shouldUseMock ? MockFamilyRepository() : FirebaseFamilyRepository()
        }
        return _familyRepository!
    }
    var memberRepository: MemberRepositoryProtocol {
        if _memberRepository == nil {
            _memberRepository = shouldUseMock ? MockMemberRepository() : FirebaseMemberRepository()
        }
        return _memberRepository!
    }
    var meetingRepository: MeetingRepositoryProtocol {
        if _meetingRepository == nil {
            _meetingRepository = shouldUseMock ? MockMeetingRepository() : FirebaseMeetingRepository()
        }
        return _meetingRepository!
    }
    var pollRepository: PollRepositoryProtocol {
        if _pollRepository == nil {
            _pollRepository = shouldUseMock ? MockPollRepository() : FirebasePollRepository()
        }
        return _pollRepository!
    }
    var recordRepository: RecordRepositoryProtocol {
        if _recordRepository == nil {
            _recordRepository = shouldUseMock ? MockRecordRepository() : FirebaseRecordRepository()
        }
        return _recordRepository!
    }
    var noteRepository: NoteRepositoryProtocol {
        if _noteRepository == nil {
            _noteRepository = shouldUseMock ? MockNoteRepository() : FirebaseNoteRepository()
        }
        return _noteRepository!
    }
    var storageRepository: StorageRepositoryProtocol {
        if _storageRepository == nil {
            _storageRepository = shouldUseMock ? MockStorageRepository() : FirebaseStorageRepository()
        }
        return _storageRepository!
    }

    private var hasSeenOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasSeenOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasSeenOnboarding") }
    }

    // MARK: - 스플래시 후 상태 결정
    func checkAuthState() {
        #if DEBUG
        if Self.useMockForScreenshots {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                currentUser = MockData.currentUser
                currentFamily = MockData.family
                members = MockData.members
                meetings = MockData.meetings
                notes = MockData.notes
                myRecordedMeetingIds = []
                averageRating = 4.8
                consecutiveWeeks = 6
                authState = .home
            }
            return
        }
        #endif

        // 애니메이션 2.4초 + 1초 대기 = 3.4초 최소 표시
        let minSplashSeconds: UInt64 = 3_400_000_000
        Task { @MainActor in
            async let minDelay: () = Task.sleep(nanoseconds: minSplashSeconds)

            let nextState: AuthState
            if let firebaseUser = Auth.auth().currentUser {
                nextState = await resolveAuthState(uid: firebaseUser.uid)
            } else if hasSeenOnboarding {
                nextState = .login
            } else {
                nextState = .onboarding
            }

            try? await minDelay
            authState = nextState
        }
    }

    // MARK: - 온보딩 완료
    func completeOnboarding() {
        hasSeenOnboarding = true
        authState = .login
    }

    // MARK: - 이메일 로그인 (디버그용)
    #if DEBUG
    func signInWithEmail(email: String, password: String, marketingConsent: Bool = false) async {
        isLoading = true
        self.error = nil
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            let uid = result.user.uid
            let user = User(
                id: uid,
                name: result.user.displayName ?? email.components(separatedBy: "@").first ?? "테스터",
                profileImageURL: nil,
                familyId: nil,
                createdAt: Date()
            )
            try await userRepository.createUserIfNeeded(user)
            try? await userRepository.recordTermsAgreement(
                userId: uid,
                version: AppConstants.Legal.termsVersion,
                marketingConsent: marketingConsent
            )
            await loadUserData(uid: uid)
        } catch {
            self.error = AppError.from(error)
        }
    }
    #endif

    // MARK: - Apple 로그인
    func signInWithApple(marketingConsent: Bool = false) async {
        isLoading = true
        self.error = nil
        defer { isLoading = false }
        do {
            let user = try await authRepository.signInWithApple()
            try await userRepository.createUserIfNeeded(user)
            try? await userRepository.recordTermsAgreement(
                userId: user.id,
                version: AppConstants.Legal.termsVersion,
                marketingConsent: marketingConsent
            )
            await loadUserData(uid: user.id)
        } catch {
            self.error = AppError.from(error)
        }
    }

    // MARK: - 유저 데이터 로드 → 화면 분기
    @MainActor
    private func loadUserData(uid: String) async {
        let next = await resolveAuthState(uid: uid)
        authState = next
    }

    @MainActor
    private func resolveAuthState(uid: String) async -> AuthState {
        await refreshFCMToken(uid: uid)

        do {
            let user = try await userRepository.getUser(id: uid)
            currentUser = user

            if let familyId = user.familyId {
                do {
                    let family = try await familyRepository.getFamily(id: familyId)
                    currentFamily = family
                    await loadHomeData()
                    return .home
                } catch {
                    // 가정이 이미 삭제됨 (관리자가 cascade 삭제한 경우 등) — stale familyId 해제
                    var updated = user
                    updated.familyId = nil
                    try? await userRepository.updateUser(updated)
                    currentUser = updated
                    return .familySetup
                }
            } else {
                return .familySetup
            }
        } catch {
            let newUser = User(
                id: uid,
                name: Auth.auth().currentUser?.displayName ?? "사용자",
                profileImageURL: nil,
                familyId: nil,
                createdAt: Date()
            )
            try? await userRepository.createUserIfNeeded(newUser)
            currentUser = newUser
            return .familySetup
        }
    }

    // 로그인 확정 시점에 현재 FCM 토큰을 Firestore로 동기화.
    // AppDelegate의 didReceiveRegistrationToken이 로그인 이전에 발화해서 유실되는 경우와
    // 번들 ID 변경 후 옛 토큰이 남아있는 경우를 모두 방어.
    private func refreshFCMToken(uid: String) async {
        do {
            let token = try await Messaging.messaging().token()
            // setData(merge:)로 문서가 없을 때도 생성. 첫 로그인 레이스 컨디션 방어.
            try await Firestore.firestore()
                .collection("users").document(uid)
                .setData(["fcmToken": token], merge: true)
        } catch {
            // 실패해도 앱 사용은 계속 가능하므로 무시
        }
    }

    // MARK: - 가정 참여 완료
    func joinedFamily(_ family: Family) {
        currentFamily = family
        if let user = currentUser {
            Task {
                var updatedUser = user
                updatedUser.familyId = family.id
                try? await userRepository.updateUser(updatedUser)
                await loadHomeData()
            }
        }
        authState = .home
    }

    // MARK: - 홈 데이터 로드
    @MainActor
    func loadHomeData() async {
        guard let familyId = currentFamily?.id else { return }
        do {
            await refreshCurrentFamily()
            meetings = try await meetingRepository.getMeetings(familyId: familyId)
            // 다른 가족 구성원이 만든 모임도 내 캘린더에 반영 (refreshMeetings와 동일 보장)
            backfillCalendarIfNeeded()
            notes = (try? await noteRepository.getNotes(familyId: familyId)) ?? []
            await refreshMembers()
            await checkMyRecords()
        } catch {
            self.error = AppError.from(error)
        }
    }

    /// family 문서만 재조회. 다른 사람이 플래너/모드를 바꾼 경우 동기화용.
    @MainActor
    func refreshCurrentFamily() async {
        guard let familyId = currentFamily?.id else { return }
        if let refreshed = try? await familyRepository.getFamily(id: familyId) {
            currentFamily = refreshed
        }
    }

    @MainActor
    func checkMyRecords() async {
        guard let familyId = currentFamily?.id,
              let userId = currentUser?.id else { return }
        var recordedIds = Set<String>()
        var allRatings: [Int] = []
        for meeting in meetings {
            if let records = try? await recordRepository.getRecords(familyId: familyId, meetingId: meeting.id) {
                if records.contains(where: { $0.memberId == userId }) {
                    recordedIds.insert(meeting.id)
                }
                allRatings.append(contentsOf: records.map(\.rating))
            }
        }
        myRecordedMeetingIds = recordedIds
        averageRating = allRatings.isEmpty ? 0 : Double(allRatings.reduce(0, +)) / Double(allRatings.count)
        consecutiveWeeks = calcConsecutiveWeeks()
    }

    private func calcConsecutiveWeeks() -> Int {
        // 월-일 기준 주차 (ISO 8601). 한국 로케일 기본은 일-토라 명시적으로 설정.
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let now = Date()

        // 모임 날짜에서 주 번호 추출 (과거 모임만)
        let meetingWeeks = Set(
            meetings
                .filter { $0.meetingDate <= now && $0.status != .cancelled }
                .map { calendar.component(.weekOfYear, from: $0.meetingDate) * 10000 + calendar.component(.yearForWeekOfYear, from: $0.meetingDate) }
        )
        // 한 겹(노트)도 그 주를 "채운" 걸로 인정 — 모임 없이 메모만 남긴 주도 연속 유지.
        let noteWeeks = Set(
            notes
                .filter { $0.date <= now }
                .map { calendar.component(.weekOfYear, from: $0.date) * 10000 + calendar.component(.yearForWeekOfYear, from: $0.date) }
        )
        let activeWeeks = meetingWeeks.union(noteWeeks)

        guard !activeWeeks.isEmpty else { return 0 }

        // 현재 주부터 과거로 연속 체크
        // 이번 주에 아직 진행된 모임이 없으면(예: 계획만 있고 날짜가 미래) 지난 주부터 시작
        var streak = 0
        var checkDate = now

        let currentKey = calendar.component(.weekOfYear, from: now) * 10000
            + calendar.component(.yearForWeekOfYear, from: now)
        if !activeWeeks.contains(currentKey) {
            guard let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now) else {
                return 0
            }
            checkDate = lastWeek
        }

        while true {
            let week = calendar.component(.weekOfYear, from: checkDate)
            let year = calendar.component(.yearForWeekOfYear, from: checkDate)
            let key = week * 10000 + year

            if activeWeeks.contains(key) {
                streak += 1
                guard let newDate = calendar.date(byAdding: .weekOfYear, value: -1, to: checkDate) else { break }
                checkDate = newDate
            } else {
                break
            }
        }

        return streak
    }

    @MainActor
    func refreshMeetings() async {
        guard let familyId = currentFamily?.id else { return }
        do {
            meetings = try await meetingRepository.getMeetings(familyId: familyId)
            // 토글 ON이면 다가오는 모임을 본인 캘린더에 backfill —
            // 가족 다른 멤버가 만든 모임도 누락 없이 등록되게 보장.
            backfillCalendarIfNeeded()
        } catch {
            self.error = AppError.from(error)
        }
    }

    /// 캘린더 토글이 켜져 있으면 현재 ~ 미래 1년 모임을 본인 캘린더에 일괄 sync.
    /// CalendarSyncService 내부에서 이미 등록된 이벤트는 update만, 신규는 create.
    @MainActor
    func backfillCalendarIfNeeded() {
        guard CalendarSyncService.shared.isEnabled,
              CalendarSyncService.shared.hasAccess else { return }
        let now = Date()
        let upcoming = meetings.filter {
            $0.meetingDate >= now.addingTimeInterval(-7 * 24 * 3600) // 지난 1주까지 포함
                && $0.status != .cancelled
        }
        CalendarSyncService.shared.syncEvents(upcoming)
    }

    @MainActor
    func refreshMembers() async {
        guard let familyId = currentFamily?.id else { return }
        do {
            var loadedMembers = try await memberRepository.getMembers(familyId: familyId)

            // members 서브컬렉션의 profileImageURL이 누락된 경우 users에서 동기화
            for i in loadedMembers.indices {
                if loadedMembers[i].profileImageURL == nil {
                    if let user = try? await userRepository.getUser(id: loadedMembers[i].id),
                       let imageURL = user.profileImageURL {
                        loadedMembers[i].profileImageURL = imageURL
                        try? await memberRepository.syncMemberProfileImage(
                            familyId: familyId,
                            memberId: loadedMembers[i].id,
                            imageURL: imageURL
                        )
                    }
                }
            }

            members = loadedMembers
        } catch {
            self.error = AppError.from(error)
        }
    }

    // MARK: - 모임 CRUD
    func createMeeting(_ meeting: Meeting) async throws -> Meeting {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        let created = try await meetingRepository.createMeeting(familyId: familyId, meeting: meeting)
        await refreshMeetings()
        // iOS 캘린더 동기화 — MainActor 격리. 토글 OFF면 no-op. 실패해도 모임 생성은 성공.
        await MainActor.run { CalendarSyncService.shared.syncEvent(for: created) }
        return created
    }

    func updateMeeting(_ meeting: Meeting) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        // 호출자가 별도로 안 채워도 항상 현재 사용자로 lastEditedBy 자동 주입.
        // 출석/콕 찌르기 같은 운영성 변경은 별도 메서드를 타므로 이 경로엔 안 들어옴.
        var updated = meeting
        if let user = currentUser {
            updated.lastEditedAt = Date()
            updated.lastEditedById = user.id
            updated.lastEditedByName = user.name
        }
        try await meetingRepository.updateMeeting(familyId: familyId, meeting: updated)
        await refreshMeetings()
        // iOS 캘린더에도 변경 반영
        await MainActor.run { CalendarSyncService.shared.syncEvent(for: updated) }
    }

    func deleteMeeting(_ meetingId: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        isLoading = true
        defer { isLoading = false }
        try await meetingRepository.deleteMeeting(familyId: familyId, meetingId: meetingId)
        await refreshMeetings()
        // 캘린더에서도 제거
        await MainActor.run { CalendarSyncService.shared.removeEvent(for: meetingId) }
    }

    // MARK: - 참석 / 참여자 / 콕 찌르기

    /// 특정 멤버의 참석 상태 변경(본인/대신 설정 공용). status가 nil이면 미정으로.
    /// 명단이 비어 있던 레거시 모임이면 이번에 가족 전원으로 명시화.
    func setAttendance(meetingId: String, memberId: String, status: Meeting.AttendanceStatus?) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        guard let meeting = meetings.first(where: { $0.id == meetingId }) else { return }
        try await meetingRepository.setAttendance(
            familyId: familyId,
            meetingId: meetingId,
            memberId: memberId,
            status: status,
            participantIds: meeting.participantIds.isEmpty ? members.map(\.id) : []
        )
        await refreshMeetings()
    }

    /// 현재 사용자의 참석 상태 변경.
    func setMyAttendance(meetingId: String, status: Meeting.AttendanceStatus?) async throws {
        guard let userId = currentUser?.id else { return }
        try await setAttendance(meetingId: meetingId, memberId: userId, status: status)
    }

    func setMeetingParticipants(meetingId: String, participantIds: [String]) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await meetingRepository.setParticipants(
            familyId: familyId,
            meetingId: meetingId,
            participantIds: participantIds
        )
        await refreshMeetings()
    }

    func sendNudge(meetingId: String, targetUserId: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        guard let user = currentUser else { return }
        try await meetingRepository.sendNudge(
            familyId: familyId,
            meetingId: meetingId,
            fromUserId: user.id,
            fromName: user.name,
            targetUserId: targetUserId
        )
    }

    // MARK: - 투표 CRUD
    func createPoll(meetingId: String, poll: Poll) async throws -> Poll {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        let created = try await pollRepository.createPoll(familyId: familyId, meetingId: meetingId, poll: poll)
        await refreshMeetings()
        return created
    }

    func vote(meetingId: String, pollId: String, optionId: String) async throws {
        guard let familyId = currentFamily?.id,
              let userId = currentUser?.id else { throw AppStateError.noFamily }
        try await pollRepository.vote(familyId: familyId, meetingId: meetingId, pollId: pollId, optionId: optionId, userId: userId)
    }

    func removeVote(meetingId: String, pollId: String, optionId: String) async throws {
        guard let familyId = currentFamily?.id,
              let userId = currentUser?.id else { throw AppStateError.noFamily }
        try await pollRepository.removeVote(familyId: familyId, meetingId: meetingId, pollId: pollId, optionId: optionId, userId: userId)
    }

    func getPolls(meetingId: String) async throws -> [Poll] {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        return try await pollRepository.getPolls(familyId: familyId, meetingId: meetingId)
    }

    func getPoll(meetingId: String, pollId: String) async throws -> Poll {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        return try await pollRepository.getPoll(familyId: familyId, meetingId: meetingId, pollId: pollId)
    }

    func deletePoll(meetingId: String, pollId: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        isLoading = true
        defer { isLoading = false }
        try await pollRepository.deletePoll(familyId: familyId, meetingId: meetingId, pollId: pollId)
        await refreshMeetings()
    }

    func addPollOption(meetingId: String, pollId: String, option: PollOption) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await pollRepository.addOption(familyId: familyId, meetingId: meetingId, pollId: pollId, option: option)
    }

    func updatePollOptions(meetingId: String, pollId: String, options: [PollOption]) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await pollRepository.updatePollOptions(familyId: familyId, meetingId: meetingId, pollId: pollId, options: options)
    }

    // MARK: - 모임 의견 (단일/후보 모드 무관)
    func getMeetingComments(meetingId: String) async throws -> [MeetingComment] {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        return try await meetingRepository.getComments(familyId: familyId, meetingId: meetingId)
    }

    /// 의견 실시간 구독. 뷰가 사라지면 `.task` 취소 → continuation.onTermination에서 listener 해제.
    func observeMeetingComments(meetingId: String) -> AsyncStream<[MeetingComment]> {
        guard let familyId = currentFamily?.id else {
            return AsyncStream { $0.finish() }
        }
        return meetingRepository.observeComments(familyId: familyId, meetingId: meetingId)
    }

    func addMeetingComment(meetingId: String, text: String) async throws -> MeetingComment {
        guard let familyId = currentFamily?.id,
              let user = currentUser else { throw AppStateError.noFamily }
        let comment = MeetingComment(
            id: UUID().uuidString,
            userId: user.id,
            userName: user.name,
            text: text,
            createdAt: Date()
        )
        return try await meetingRepository.addComment(familyId: familyId, meetingId: meetingId, comment: comment)
    }

    func updateMeetingComment(meetingId: String, commentId: String, text: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await meetingRepository.updateComment(familyId: familyId, meetingId: meetingId, commentId: commentId, text: text)
    }

    func deleteMeetingComment(meetingId: String, commentId: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await meetingRepository.deleteComment(familyId: familyId, meetingId: meetingId, commentId: commentId)
    }

    // MARK: - 기록 CRUD
    @MainActor
    func createRecord(meetingId: String, record: MeetingRecord) async throws -> MeetingRecord {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        let created = try await recordRepository.createRecord(familyId: familyId, meetingId: meetingId, record: record)
        myRecordedMeetingIds.insert(meetingId)
        return created
    }

    func getRecords(meetingId: String) async throws -> [MeetingRecord] {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        return try await recordRepository.getRecords(familyId: familyId, meetingId: meetingId)
    }

    func updateRecord(meetingId: String, record: MeetingRecord) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await recordRepository.updateRecord(familyId: familyId, meetingId: meetingId, record: record)
    }

    func deleteRecord(meetingId: String, recordId: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        isLoading = true
        defer { isLoading = false }
        try await recordRepository.deleteRecord(familyId: familyId, meetingId: meetingId, recordId: recordId)
    }

    // MARK: - 한 겹(노트) CRUD
    @MainActor
    func refreshNotes() async {
        guard let familyId = currentFamily?.id else { return }
        if let loaded = try? await noteRepository.getNotes(familyId: familyId) {
            notes = loaded
            // 노트가 연속 주에 반영되므로 새로고침 때마다 재계산.
            consecutiveWeeks = calcConsecutiveWeeks()
        }
    }

    @MainActor
    func createNote(_ note: Note) async throws -> Note {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        let created = try await noteRepository.createNote(familyId: familyId, note: note)
        await refreshNotes()
        return created
    }

    @MainActor
    func updateNote(_ note: Note) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await noteRepository.updateNote(familyId: familyId, note: note)
        await refreshNotes()
    }

    @MainActor
    func deleteNote(_ noteId: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        isLoading = true
        defer { isLoading = false }
        try await noteRepository.deleteNote(familyId: familyId, noteId: noteId)
        await refreshNotes()
    }

    // MARK: - 구성원 관리
    func removeMember(_ memberId: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        isLoading = true
        defer { isLoading = false }
        try await memberRepository.removeMember(familyId: familyId, memberId: memberId)
        await refreshMembers()
    }

    func updateRotationOrder(_ memberOrders: [(memberId: String, order: Int)]) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await memberRepository.updateRotationOrder(familyId: familyId, memberOrders: memberOrders)
        await refreshMembers()
    }

    // MARK: - 가정 관리
    func generateInviteCode() async throws -> String {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        return try await familyRepository.generateInviteCode(familyId: familyId)
    }

    func leaveFamily() async throws {
        guard let family = currentFamily,
              let userId = currentUser?.id else { throw AppStateError.noFamily }
        isLoading = true
        defer { isLoading = false }

        try await performLeaveFamily(userId: userId, family: family, members: members)

        currentFamily = nil
        members = []
        meetings = []
        notes = []
        authState = .familySetup
    }

    /// leaveFamily의 순수 데이터 작업 파트. UI/state 전환은 포함하지 않음.
    /// deleteAccount처럼 leaveFamily 도중 화면 전환(.familySetup)이 일어나면 안 되는 호출자를 위해 분리.
    private func performLeaveFamily(userId: String, family: Family, members: [Member]) async throws {
        let familyId = family.id
        if members.count <= 1 {
            // 마지막 구성원이 나가면 가정 자체를 삭제
            try await familyRepository.deleteFamily(id: familyId)
        } else {
            // 관리자가 나가면 rotationOrder 기준 다음 구성원에게 역할 자동 이전.
            // 이전이 실패해도 멤버 탈퇴는 계속 진행해 "관리자만 이전된 좀비 상태" 방지.
            if family.adminId == userId {
                if let nextAdmin = members
                    .filter({ $0.id != userId })
                    .sorted(by: { $0.rotationOrder < $1.rotationOrder })
                    .first {
                    try? await memberRepository.transferAdmin(familyId: familyId, newAdminId: nextAdmin.id)
                }
            }
            // 나간 사람의 모임 plannerName·기록 memberName을 "Guest"로 바꾸고 투표 이력 제거
            try? await anonymizeUserContent(familyId: familyId, userId: userId)
            try await memberRepository.removeMember(familyId: familyId, memberId: userId)
        }

        if var updatedUser = currentUser {
            updatedUser.familyId = nil
            try? await userRepository.updateUser(updatedUser)
            currentUser = updatedUser
        }
    }

    /// 나간 구성원의 meetings.plannerName / records.memberName을 "Guest"로 치환하고
    /// polls 내 본인 투표 기록을 제거. 모임·기록 데이터 자체는 보존.
    private func anonymizeUserContent(familyId: String, userId: String) async throws {
        try await renameUserContent(familyId: familyId, userId: userId, newName: "Guest")
        try await removePollVotes(familyId: familyId, userId: userId)
    }

    /// 가정 내 모든 polls를 훑어 options[].voterIds에서 userId 제거 + voteCount 보정.
    /// 익명 투표(isAnonymous=true)는 voterIds 자체가 없어 건드릴 필요 없음.
    private func removePollVotes(familyId: String, userId: String) async throws {
        let db = Firestore.firestore()
        let meetingsSnap = try await db.collection("families").document(familyId)
            .collection("meetings").getDocuments()
        for meetingDoc in meetingsSnap.documents {
            let pollsSnap = try? await meetingDoc.reference.collection("polls").getDocuments()
            for pollDoc in pollsSnap?.documents ?? [] {
                guard var options = pollDoc.data()["options"] as? [[String: Any]] else { continue }
                var changed = false
                for i in options.indices {
                    var voterIds = options[i]["voterIds"] as? [String] ?? []
                    guard voterIds.contains(userId) else { continue }
                    voterIds.removeAll { $0 == userId }
                    options[i]["voterIds"] = voterIds
                    options[i]["voteCount"] = voterIds.count
                    changed = true
                }
                if changed {
                    try? await pollDoc.reference.updateData(["options": options])
                }
            }
        }
    }

    /// 재참여한 구성원의 과거 모임·기록의 plannerName / memberName을 현재 이름으로 복원.
    /// "Guest"였든 다른 값이었든 무조건 최신 이름으로 덮어씀 → UI 일관성 확보.
    func restoreUserContentName(familyId: String, userId: String, newName: String) async throws {
        try await renameUserContent(familyId: familyId, userId: userId, newName: newName)
    }

    private func renameUserContent(familyId: String, userId: String, newName: String) async throws {
        let db = Firestore.firestore()
        let meetingsRef = db.collection("families").document(familyId).collection("meetings")

        let meetingsSnapshot = try await meetingsRef.whereField("plannerId", isEqualTo: userId).getDocuments()
        for doc in meetingsSnapshot.documents {
            try? await doc.reference.updateData(["plannerName": newName])
        }

        let recordsSnapshot = try? await db.collectionGroup("records")
            .whereField("memberId", isEqualTo: userId)
            .getDocuments()
        for doc in recordsSnapshot?.documents ?? [] {
            guard doc.reference.path.contains("families/\(familyId)/") else { continue }
            try? await doc.reference.updateData(["memberName": newName])
        }
    }

    func deleteFamily() async throws {
        guard let family = currentFamily,
              let userId = currentUser?.id else { throw AppStateError.noFamily }
        guard family.adminId == userId else { throw AppStateError.notAdmin }
        guard members.count <= 1 else { throw AppStateError.familyHasOtherMembers }
        isLoading = true
        defer { isLoading = false }
        try await familyRepository.deleteFamily(id: family.id)
        if var updatedUser = currentUser {
            updatedUser.familyId = nil
            try await userRepository.updateUser(updatedUser)
            currentUser = updatedUser
        }
        currentFamily = nil
        members = []
        meetings = []
        notes = []
        authState = .familySetup
    }

    // MARK: - 프로필 수정
    // MARK: - 가정 이름 변경
    @MainActor
    func updateFamilyName(_ name: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await familyRepository.updateFamilyName(familyId: familyId, name: name)
        currentFamily?.name = name
    }

    @MainActor
    func updateRotationMode(_ mode: String) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await familyRepository.updateRotationMode(familyId: familyId, mode: mode)
        currentFamily?.rotationMode = mode
    }

    // MARK: - 알림 설정
    @MainActor
    func loadNotificationSettings() async -> NotificationSettings {
        guard let userId = currentUser?.id else { return NotificationSettings() }
        return (try? await userRepository.loadNotificationSettings(userId: userId)) ?? NotificationSettings()
    }

    @MainActor
    func updateNotificationSettings(_ settings: NotificationSettings) async {
        guard let userId = currentUser?.id else { return }
        do {
            try await userRepository.updateNotificationSettings(userId: userId, settings: settings)
        } catch {
            // 조용히 삼키면 사용자가 끈 알림이 저장 안 된 채 켜져 보일 수 있음 — 표면화
            self.error = AppError.from(error)
        }
    }

    @MainActor
    func updateCurrentPlannerIndex(_ index: Int) async throws {
        guard let familyId = currentFamily?.id else { throw AppStateError.noFamily }
        try await familyRepository.updateCurrentPlannerIndex(familyId: familyId, index: index)
        currentFamily?.currentPlannerIndex = index
    }

    @MainActor
    func updateProfile(name: String, profileImageURL: String?) async throws {
        guard var user = currentUser else { return }
        user.name = name
        user.profileImageURL = profileImageURL
        try await userRepository.updateUser(user)
        currentUser = user

        // members 서브컬렉션도 동기화 (실패해도 저장은 성공으로 처리)
        if let familyId = currentFamily?.id {
            try? await memberRepository.updateMemberProfile(
                familyId: familyId,
                memberId: user.id,
                name: name,
                profileImageURL: profileImageURL
            )
            await refreshMembers()
        }
    }

    // MARK: - 프로필 사진 업로드
    func uploadProfileImage(_ image: UIImage) async throws {
        guard var user = currentUser else { return }
        guard let data = ImageProcessor.resizeAndCompress(image, maxSize: 256, quality: 0.5) else { return }
        let url = try await storageRepository.uploadProfileImage(userId: user.id, imageData: data)
        user.profileImageURL = url
        try await userRepository.updateUser(user)
        currentUser = user
    }

    // MARK: - 로그아웃
    func signOut() {
        // 로그아웃하는 유저의 Firestore fcmToken을 먼저 비움.
        // 그대로 두면 같은 기기에 다른 계정이 로그인했을 때 이전 유저용 푸시가
        // 현 기기로 배달될 수 있다. Auth signOut 이후엔 uid를 못 읽으므로 먼저 처리.
        if let uid = currentUser?.id {
            Firestore.firestore()
                .collection("users").document(uid)
                .updateData(["fcmToken": FieldValue.delete()]) { _ in }
        }
        try? authRepository.signOut()
        currentUser = nil
        currentFamily = nil
        members = []
        meetings = []
        notes = []
        authState = .login
    }

    // MARK: - 계정 삭제
    /// 보안상 민감 작업이라 항상 Apple 재인증부터 진행.
    /// 재인증이 끝난 뒤에만 데이터 cleanup + Auth 삭제를 해서
    /// 사용자가 중간에 취소해도 데이터가 일부만 지워진 좀비 상태가 되지 않도록 보장.
    func deleteAccount() async throws {
        isLoading = true
        defer { isLoading = false }

        // 1. Apple 재인증 (사용자 취소 시 throw → 이 지점 이전엔 아무 것도 건드리지 않음)
        _ = try await authRepository.signInWithApple()

        // 2. Firestore · Storage · 가족 데이터 cleanup
        try await cleanupUserDataBeforeAuthDeletion()

        // 3. Firebase Auth 계정 삭제
        try await authRepository.deleteAccount()

        // 4. 상태 초기화
        finalizeAccountDeletion()
    }

    /// Auth 삭제 전에 사용자와 관련된 Firestore·Storage 데이터를 모두 제거.
    /// 순서가 중요: Auth가 없어지면 보안 규칙상 문서 수정 권한도 사라짐.
    private func cleanupUserDataBeforeAuthDeletion() async throws {
        guard let userId = currentUser?.id else { return }

        // 1. 가족에 속해있으면 먼저 나가기.
        //    leaveFamily() 대신 performLeaveFamily를 호출해 화면 전환(.familySetup)이
        //    deleteAccount 도중에 발화하지 않게 한다. 실패는 그대로 전파 —
        //    try?로 삼키면 고아 가정이 생긴 뒤 users·Auth만 지워지기 때문.
        if let family = currentFamily {
            try await performLeaveFamily(userId: userId, family: family, members: members)
        }

        // 2. Storage 프로필 이미지 삭제 (없을 수 있으니 실패 허용)
        try? await storageRepository.deleteImage(path: "users/\(userId)/profile.jpg")

        // 3. Firestore users 문서 삭제 — 실패하면 Auth 삭제 진행 금지.
        //    Auth가 사라지면 이 문서에 다시 접근할 보안 규칙 권한도 없어진다.
        try await Firestore.firestore().collection("users").document(userId).delete()
    }

    private func finalizeAccountDeletion() {
        currentUser = nil
        currentFamily = nil
        members = []
        meetings = []
        notes = []
        authState = .login
    }
}

// MARK: - AppState Error
enum AppStateError: LocalizedError {
    case noFamily
    case notAdmin
    case familyHasOtherMembers

    var errorDescription: String? {
        switch self {
        case .noFamily: return "가정 정보를 찾을 수 없습니다"
        case .notAdmin: return "관리자만 수행할 수 있는 작업입니다"
        case .familyHasOtherMembers:
            return "다른 구성원이 있어 가정을 삭제할 수 없습니다.\n먼저 구성원을 내보내거나 나가기를 요청해주세요."
        }
    }
}
