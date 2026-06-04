import Foundation
import EventKit

/// iOS 캘린더(EventKit) 동기화 — 본인 폰 기본 캘린더에 모임을 자동 등록·갱신·삭제.
///
/// 설계 원칙
/// - 토글 OFF / 권한 없음 → 모든 메서드 silent no-op. 절대 throw 안 함.
/// - 기기마다 독립. UserDefaults에 `[meetingId: eventIdentifier]` 매핑 저장.
/// - 매핑 손실(앱 재설치 등) 시 캘린더 이벤트 notes 안에 박아둔 `[겹겹:meetingId=…]`
///   태그로 검색해서 dedup.
/// - 동기화는 best-effort. 실패해도 앱의 다른 기능은 0% 영향.
@MainActor
final class CalendarSyncService {
    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()
    private let toggleKey = "calendarSync.enabled"
    private let mappingKey = "calendarSync.eventMap"

    private init() {}

    // MARK: - Toggle

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: toggleKey) }
        set { UserDefaults.standard.set(newValue, forKey: toggleKey) }
    }

    // MARK: - 권한

    /// 사용자에게 권한 prompt. iOS 17+는 requestFullAccessToEvents, 그 이하는 requestAccess.
    /// 결과: 성공 시 true, 거부/실패 시 false. throw 안 함.
    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            return (try? await eventStore.requestAccess(to: .event)) ?? false
        }
    }

    /// 현재 권한 상태. .fullAccess(iOS17+) 또는 legacy .authorized면 동기화 가능.
    var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    // MARK: - 모임 동기화

    /// 모임 1개를 캘린더에 등록(없으면 만들고, 있으면 갱신).
    /// 토글 OFF / 권한 없음 / cancelled 모임이면 no-op.
    func syncEvent(for meeting: Meeting) {
        guard isEnabled, hasAccess else { return }
        guard meeting.status != .cancelled else {
            // 취소된 모임이 이미 등록돼 있으면 제거
            removeEvent(for: meeting.id)
            return
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else { return }

        // 1) 기존 매핑 또는 notes 태그로 기존 이벤트 찾기
        let existingId = eventMapping[meeting.id]
            ?? findEventByMeetingId(meeting.id, in: calendar)

        let event: EKEvent
        if let existingId, let existing = eventStore.event(withIdentifier: existingId) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
        }

        // 2) 필드 갱신
        event.title = "겹겹 · \(meeting.displayPlace)"
        event.startDate = meeting.meetingDate
        // 우리 모델에 endDate 없으니 기본 2시간으로 고정. 추후 모델 확장 시 교체.
        event.endDate = meeting.meetingDate.addingTimeInterval(2 * 3600)
        event.location = meeting.place.isEmpty ? nil : meeting.place
        event.notes = buildNotes(meeting: meeting)

        // 3) 알람: 1시간 전. 중복 방지 위해 기존 알람 없을 때만 추가.
        if (event.alarms ?? []).isEmpty {
            event.addAlarm(EKAlarm(relativeOffset: -3600))
        }

        // 4) 저장
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            saveMapping(meetingId: meeting.id, eventId: event.eventIdentifier)
        } catch {
            // silent fail — 앱 사용에 영향 없음
        }
    }

    /// 매핑된 캘린더 이벤트를 제거. 매핑 없거나 이벤트 없으면 no-op.
    func removeEvent(for meetingId: String) {
        guard isEnabled, hasAccess else {
            // 토글 OFF여도 매핑은 정리해서 stale 안 남게
            removeMapping(meetingId: meetingId)
            return
        }
        guard let eventId = eventMapping[meetingId],
              let event = eventStore.event(withIdentifier: eventId) else {
            removeMapping(meetingId: meetingId)
            return
        }
        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        } catch {
            // silent fail
        }
        removeMapping(meetingId: meetingId)
    }

    /// 여러 모임을 일괄 sync — backfill용. 다가오는 모임 위주.
    func syncEvents(_ meetings: [Meeting]) {
        guard isEnabled, hasAccess else { return }
        for meeting in meetings {
            syncEvent(for: meeting)
        }
    }

    /// 토글 OFF 시 우리가 만든 이벤트들 일괄 삭제. 사용자 동의 후 호출.
    func purgeAllEvents() {
        guard hasAccess else {
            UserDefaults.standard.removeObject(forKey: mappingKey)
            return
        }
        for (_, eventId) in eventMapping {
            if let event = eventStore.event(withIdentifier: eventId) {
                try? eventStore.remove(event, span: .thisEvent, commit: false)
            }
        }
        try? eventStore.commit()
        UserDefaults.standard.removeObject(forKey: mappingKey)
    }

    // MARK: - 매핑 저장소

    private var eventMapping: [String: String] {
        UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
    }

    private func saveMapping(meetingId: String, eventId: String) {
        var map = eventMapping
        map[meetingId] = eventId
        UserDefaults.standard.set(map, forKey: mappingKey)
    }

    private func removeMapping(meetingId: String) {
        var map = eventMapping
        map[meetingId] = nil
        UserDefaults.standard.set(map, forKey: mappingKey)
    }

    // MARK: - 매핑 손실 시 폴백

    /// notes에 박아둔 `[겹겹:meetingId=…]` 태그로 캘린더 이벤트 검색.
    /// 앱 재설치 / UserDefaults 초기화 시 중복 등록 방지.
    private func findEventByMeetingId(_ meetingId: String, in calendar: EKCalendar) -> String? {
        let now = Date()
        // 과거 90일 ~ 미래 1년 윈도 — 의미 있는 모임은 거의 이 범위 안
        let predicate = eventStore.predicateForEvents(
            withStart: now.addingTimeInterval(-90 * 24 * 3600),
            end: now.addingTimeInterval(365 * 24 * 3600),
            calendars: [calendar]
        )
        let tag = meetingIdTag(meetingId)
        for event in eventStore.events(matching: predicate) {
            if event.notes?.contains(tag) == true {
                return event.eventIdentifier
            }
        }
        return nil
    }

    // MARK: - Notes 빌드

    private func meetingIdTag(_ id: String) -> String { "[겹겹:meetingId=\(id)]" }

    private func buildNotes(meeting: Meeting) -> String {
        var lines: [String] = []
        if let activity = meeting.activity, !activity.isEmpty {
            lines.append("활동: \(activity)")
        }
        if !meeting.plannerName.isEmpty {
            lines.append("주최: \(meeting.plannerName)")
        }
        lines.append("")
        lines.append("겹겹에서 자동 생성됨")
        // dedup 태그 — 사용자 눈엔 거슬리지만 매핑 손실 복구에 필수
        lines.append(meetingIdTag(meeting.id))
        return lines.joined(separator: "\n")
    }
}
