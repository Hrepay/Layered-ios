import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import {setGlobalOptions} from "firebase-functions/v2";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp, FieldValue} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";

initializeApp();
const db = getFirestore();

setGlobalOptions({maxInstances: 10, region: "us-east1"});

// ============================================================
// 1. 플래너 자동 로테이션 — 매주 월요일 오전 9시 (KST)
// ============================================================
export const rotatePlanner = onSchedule(
  {schedule: "0 0 * * 1", timeZone: "Asia/Seoul"},
  async () => {
    const families = await db.collection("families").get();

    for (const familyDoc of families.docs) {
      const data = familyDoc.data();
      const rotationMode = data.rotationMode || "auto";
      if (rotationMode !== "auto") continue;

      const membersSnap = await familyDoc.ref
        .collection("members")
        .orderBy("rotationOrder")
        .get();

      if (membersSnap.empty) continue;

      const memberCount = membersSnap.size;
      const currentIndex = data.currentPlannerIndex || 0;
      const nextIndex = (currentIndex + 1) % memberCount;

      await familyDoc.ref.update({currentPlannerIndex: nextIndex});

      console.log(
        `Family ${familyDoc.id}: ` +
        `planner ${currentIndex} -> ${nextIndex}`
      );
    }
  }
);

// ============================================================
// 2. 모임 등록 알림 — Firestore Trigger
// ============================================================
export const onMeetingCreated = onDocumentCreated(
  "families/{familyId}/meetings/{meetingId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const meetingData = snapshot.data();
    const familyId = event.params.familyId;

    const membersSnap = await db
      .collection("families")
      .doc(familyId)
      .collection("members")
      .get();

    const tokens: string[] = [];
    for (const memberDoc of membersSnap.docs) {
      const userDoc = await db
        .collection("users")
        .doc(memberDoc.id).get();
      const userData = userDoc.data();
      const userTokens = deviceTokens(userData);
      const notificationsEnabled =
        userData?.notificationsEnabled !== false;
      const notifyMeetingCreated =
        userData?.notifyMeetingCreated !== false;
      if (userTokens.length > 0 &&
          notificationsEnabled && notifyMeetingCreated) {
        tokens.push(...userTokens);
      }
    }

    if (tokens.length === 0) return;

    const place = meetingData.place || "장소 미정";
    const planner = meetingData.plannerName || "누군가";
    const date = meetingData.meetingDate?.toDate?.();
    let dateStr = "";
    if (date) {
      // Cloud Functions 런타임(us-east1)은 UTC 기준이라
      // getHours 등을 그대로 쓰면 KST와 9시간 어긋남.
      // UTC 기준 Date를 +9h 이동시킨 뒤 getUTC* 계열로 읽어 KST 값을 추출.
      const kst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
      const m = kst.getUTCMonth() + 1;
      const d = kst.getUTCDate();
      const days = ["일", "월", "화", "수", "목", "금", "토"];
      const day = days[kst.getUTCDay()];
      const h = kst.getUTCHours();
      const mm = kst.getUTCMinutes();
      const ampm = h < 12 ? "오전" : "오후";
      const h12 = h % 12 || 12;
      const mmStr = mm > 0 ? ` ${mm}분` : "";
      dateStr = ` · ${m}월 ${d}일 (${day}) ${ampm} ${h12}시${mmStr}`;
    }
    await sendMulticastAndCleanup(
      tokens,
      {
        notification: {
          title: `${planner}님이 가족 모임을 등록했어요!`,
          body: `${place}${dateStr}`,
        },
      },
      "MeetingCreated"
    );
  }
);

// ============================================================
// 3. 모임 수정 알림 — Firestore Trigger
// ============================================================
// 가족 누구나 모임을 수정할 수 있어서, 다른 멤버에게도 즉시 알린다.
// - lastEditedById를 보고 본인은 수신 대상에서 제외 (자기 수정 알림 방지)
// - 의미 있는 필드(시간/장소/활동/상태/투표 여부)가 바뀐 경우에만 트리거.
//   출석 변경/콕 찌르기 같은 운영성 변경은 무시.
export const onMeetingUpdated = onDocumentUpdated(
  "families/{familyId}/meetings/{meetingId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    // 의미 있는 변경 필드 진단
    const changes: string[] = [];
    const beforeDateMs =
      (before.meetingDate as Timestamp | undefined)?.toMillis() ?? 0;
    const afterDateMs =
      (after.meetingDate as Timestamp | undefined)?.toMillis() ?? 0;
    if (beforeDateMs !== afterDateMs) changes.push("시간");
    if ((before.place ?? "") !== (after.place ?? "")) changes.push("장소");
    if ((before.activity ?? "") !== (after.activity ?? "")) {
      changes.push("활동");
    }
    if ((before.status ?? "") !== (after.status ?? "")) changes.push("상태");
    if ((before.hasPoll ?? false) !== (after.hasPoll ?? false)) {
      changes.push("투표");
    }
    if (changes.length === 0) return;

    const editorId = after.lastEditedById as string | undefined;
    // lastEditedById가 비어 있으면 AppState를 거치지 않은 변경(예: Functions 자체 업데이트).
    // 식별 가능한 편집자가 없으면 알림 발송 스킵 → 자기 자신에게 푸시 가는 사고 방지.
    if (!editorId) return;

    const editorName =
      (after.lastEditedByName as string | undefined) || "누군가";
    const familyId = event.params.familyId;

    const membersSnap = await db
      .collection("families")
      .doc(familyId)
      .collection("members")
      .get();

    const tokens: string[] = [];
    for (const memberDoc of membersSnap.docs) {
      if (memberDoc.id === editorId) continue; // 편집자 본인 제외
      const userDoc = await db
        .collection("users").doc(memberDoc.id).get();
      const userData = userDoc.data();
      const userTokens = deviceTokens(userData);
      const notificationsEnabled =
        userData?.notificationsEnabled !== false;
      const notifyMeetingUpdated =
        userData?.notifyMeetingUpdated !== false;
      if (userTokens.length > 0 &&
          notificationsEnabled && notifyMeetingUpdated) {
        tokens.push(...userTokens);
      }
    }
    if (tokens.length === 0) return;

    // 본문: 변경된 필드 라벨 결합
    const changesText = changes.join("·");
    const place = (after.place as string | undefined) || "";
    const hasPoll = after.hasPoll === true;
    let contextText: string;
    if (place.length > 0) {
      contextText = place;
    } else if (hasPoll) {
      contextText = "장소 투표 중인 모임";
    } else {
      contextText = "장소 미정 모임";
    }

    await sendMulticastAndCleanup(
      tokens,
      {
        notification: {
          title: `${editorName}님이 모임 ${changesText}을 변경했어요`,
          body: contextText,
        },
        // 푸시 탭 시 해당 모임 상세로 이동
        data: {
          type: "meetingAttendance",
          meetingId: event.params.meetingId,
        },
      },
      "MeetingUpdated"
    );
  }
);

// ============================================================
// 4. 플래너 리마인드 알림 — 매일 오전 10시 (KST)
// ============================================================
export const remindPlanner = onSchedule(
  {schedule: "0 10 * * *", timeZone: "Asia/Seoul"},
  async () => {
    const now = new Date();
    const families = await db.collection("families").get();

    for (const familyDoc of families.docs) {
      const data = familyDoc.data();

      const startOfWeek = getStartOfWeek(now);
      const endOfWeek = new Date(startOfWeek);
      endOfWeek.setDate(endOfWeek.getDate() + 7);

      const meetingsSnap = await familyDoc.ref
        .collection("meetings")
        .where(
          "meetingDate", ">=",
          Timestamp.fromDate(startOfWeek)
        )
        .where(
          "meetingDate", "<",
          Timestamp.fromDate(endOfWeek)
        )
        .get();

      if (!meetingsSnap.empty) continue;

      const idx = data.currentPlannerIndex || 0;
      const membersSnap = await familyDoc.ref
        .collection("members")
        .orderBy("rotationOrder")
        .get();

      if (membersSnap.empty) continue;

      const plannerDoc =
        membersSnap.docs[idx % membersSnap.size];
      if (!plannerDoc) continue;

      const userDoc = await db
        .collection("users")
        .doc(plannerDoc.id)
        .get();
      const userData = userDoc.data();
      const userTokens = deviceTokens(userData);
      const notificationsEnabled =
        userData?.notificationsEnabled !== false;
      const notifyPlannerReminder =
        userData?.notifyPlannerReminder !== false;

      if (userTokens.length === 0) continue;
      if (!notificationsEnabled || !notifyPlannerReminder) continue;

      const familyName = data.name || "가정";
      // 단일 send는 multicast helper를 쓸 수 없어 직접 처리.
      // 실패 에러 코드가 stale token이면 정리.
      for (const token of userTokens) {
        try {
          await getMessaging().send({
            notification: {
              title: "이번 주 모임을 계획해주세요!",
              body: `${familyName}의 플래너로 지정되었어요.`,
            },
            token,
          });
          console.log(
            `Reminder: ${plannerDoc.id} in ${familyDoc.id}`
          );
        } catch (error) {
          const code = (error as {code?: string})?.code;
          console.error(
            `Reminder error (${plannerDoc.id}): code=${code}`, error
          );
          if (code && STALE_TOKEN_CODES.has(code)) {
            await cleanupInvalidTokens([token]);
          }
        }
      }
    }
  }
);

// ============================================================
// 4b. 모임 의견 알림 — Firestore Trigger
// ============================================================
// 가족 멤버가 모임에 의견을 남기면 나머지 가족에게 푸시.
// 작성자 본인은 알림 수신에서 제외.
export const onMeetingCommentCreated = onDocumentCreated(
  "families/{familyId}/meetings/{meetingId}/comments/{commentId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const commentData = snapshot.data();
    const familyId = event.params.familyId;
    const meetingId = event.params.meetingId;

    const authorId = commentData.userId as string | undefined;
    const authorName =
      (commentData.userName as string | undefined) || "누군가";
    const rawText = (commentData.text as string | undefined) || "";
    // FCM payload 보호: 60자 + 말줄임
    const preview =
      rawText.length > 60 ? rawText.slice(0, 60) + "…" : rawText;

    // 모임 장소 (후보 모드면 빈 문자열 → fallback)
    let meetingContext = "이번 모임";
    try {
      const meetingDoc = await db
        .collection("families").doc(familyId)
        .collection("meetings").doc(meetingId)
        .get();
      const place = meetingDoc.data()?.place as string | undefined;
      if (place && place.length > 0) meetingContext = place;
      else if (meetingDoc.data()?.hasPoll) meetingContext = "장소 투표 중인 모임";
    } catch (e) {
      console.error("Meeting fetch failed:", e);
    }

    // 토큰 수집 — 작성자 제외 + notifyMeetingComment !== false
    const membersSnap = await db
      .collection("families").doc(familyId)
      .collection("members").get();

    const tokens: string[] = [];
    for (const memberDoc of membersSnap.docs) {
      if (memberDoc.id === authorId) continue;
      const userDoc = await db
        .collection("users").doc(memberDoc.id).get();
      const userData = userDoc.data();
      const userTokens = deviceTokens(userData);
      const notificationsEnabled =
        userData?.notificationsEnabled !== false;
      const notifyMeetingComment =
        userData?.notifyMeetingComment !== false;
      if (userTokens.length > 0 &&
          notificationsEnabled && notifyMeetingComment) {
        tokens.push(...userTokens);
      }
    }

    if (tokens.length === 0) return;

    await sendMulticastAndCleanup(
      tokens,
      {
        notification: {
          title: `${authorName}님이 의견을 남겼어요`,
          body: `${meetingContext} · ${preview}`,
        },
        // 푸시 탭 시 iOS가 해당 모임의 의견 화면으로 deep-link.
        data: {
          type: "meetingComment",
          meetingId,
        },
      },
      "CommentNotification"
    );
  }
);

// ============================================================
// 4b-2. 모임 후기 알림 — Firestore Trigger
// ============================================================
// 가족 멤버가 모임 후기를 남기면 나머지 가족에게 푸시.
// 작성자 본인은 제외, 수정(update)은 알림 발송 대상이 아님 — onDocumentCreated만 사용.
export const onMeetingRecordCreated = onDocumentCreated(
  "families/{familyId}/meetings/{meetingId}/records/{recordId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const recordData = snapshot.data();
    const familyId = event.params.familyId;
    const meetingId = event.params.meetingId;

    const authorId = recordData.memberId as string | undefined;
    const authorName =
      (recordData.memberName as string | undefined) || "누군가";
    const rating = (recordData.rating as number | undefined) || 0;
    const rawComment = (recordData.comment as string | undefined) || "";
    // FCM payload 보호: 60자 + 말줄임
    const preview =
      rawComment.length > 60 ? rawComment.slice(0, 60) + "…" : rawComment;

    // 모임 장소 (후보 모드면 fallback)
    let meetingContext = "이번 모임";
    try {
      const meetingDoc = await db
        .collection("families").doc(familyId)
        .collection("meetings").doc(meetingId)
        .get();
      const meetingData = meetingDoc.data();
      const place = meetingData?.place as string | undefined;
      if (place && place.length > 0) meetingContext = place;
      else if (meetingData?.hasPoll) meetingContext = "장소 투표한 모임";
    } catch (e) {
      console.error("Meeting fetch failed:", e);
    }

    // 본문: "{장소} · ⭐{별점} {소감}" — 별점/소감이 없으면 자동 생략
    const ratingPart = rating > 0 ? `⭐${rating}` : "";
    const detailPart = [ratingPart, preview].filter(Boolean).join(" ");
    const body = [meetingContext, detailPart].filter(Boolean).join(" · ");

    // 토큰 수집 — 작성자 제외 + notifyMeetingRecord !== false
    const membersSnap = await db
      .collection("families").doc(familyId)
      .collection("members").get();

    const tokens: string[] = [];
    for (const memberDoc of membersSnap.docs) {
      if (memberDoc.id === authorId) continue;
      const userDoc = await db
        .collection("users").doc(memberDoc.id).get();
      const userData = userDoc.data();
      const userTokens = deviceTokens(userData);
      const notificationsEnabled =
        userData?.notificationsEnabled !== false;
      const notifyMeetingRecord =
        userData?.notifyMeetingRecord !== false;
      if (userTokens.length > 0 &&
          notificationsEnabled && notifyMeetingRecord) {
        tokens.push(...userTokens);
      }
    }

    if (tokens.length === 0) return;

    await sendMulticastAndCleanup(
      tokens,
      {
        notification: {
          title: `${authorName}님이 후기를 남겼어요`,
          body,
        },
        // 푸시 탭 시 iOS가 해당 모임의 RecordDetailView로 deep-link.
        data: {
          type: "meetingRecord",
          meetingId,
        },
      },
      "RecordNotification"
    );
  }
);

// ============================================================
// 4c. 모임 D-Day 알림 — 매일 자정 (KST)
// ============================================================
// 오늘 날짜 모임이 있는 가정의 모든 멤버에게 푸시.
// 본문: "오늘 {가족명} 모임이 있어요 — {장소}"
export const remindMeetingDDay = onSchedule(
  {schedule: "0 0 * * *", timeZone: "Asia/Seoul"},
  async () => {
    // 실행 시각 기준 KST 오늘 00:00 ~ 내일 00:00 범위 계산.
    // 런타임은 UTC라 KST 벽시계로 내림 후 -9h 해서 UTC Date로 변환.
    const now = new Date();
    const kstNow = new Date(now.getTime() + 9 * 60 * 60 * 1000);
    const kstMidnight = new Date(Date.UTC(
      kstNow.getUTCFullYear(),
      kstNow.getUTCMonth(),
      kstNow.getUTCDate(),
      0, 0, 0
    ));
    const todayStart = new Date(
      kstMidnight.getTime() - 9 * 60 * 60 * 1000
    );
    const todayEnd = new Date(
      todayStart.getTime() + 24 * 60 * 60 * 1000
    );

    const families = await db.collection("families").get();

    for (const familyDoc of families.docs) {
      const meetingsSnap = await familyDoc.ref
        .collection("meetings")
        .where(
          "meetingDate", ">=",
          Timestamp.fromDate(todayStart)
        )
        .where(
          "meetingDate", "<",
          Timestamp.fromDate(todayEnd)
        )
        .get();

      if (meetingsSnap.empty) continue;

      const familyName = familyDoc.data().name || "가족";

      // 멤버 토큰 수집 (notifyMeetingDDay !== false 인 멤버만)
      const membersSnap = await familyDoc.ref
        .collection("members").get();
      const tokens: string[] = [];
      for (const memberDoc of membersSnap.docs) {
        const userDoc = await db
          .collection("users").doc(memberDoc.id).get();
        const userData = userDoc.data();
        const userTokens = deviceTokens(userData);
        const notificationsEnabled =
          userData?.notificationsEnabled !== false;
        const notifyMeetingDDay =
          userData?.notifyMeetingDDay !== false;
        if (userTokens.length > 0 &&
            notificationsEnabled && notifyMeetingDDay) {
          tokens.push(...userTokens);
        }
      }
      if (tokens.length === 0) continue;

      // 같은 날 여러 모임이 있을 수도 있으니 각각 별도 푸시.
      for (const meetingDoc of meetingsSnap.docs) {
        const data = meetingDoc.data();
        const rawPlace = (data.place as string | undefined) || "";
        const hasPoll = data.hasPoll === true;
        let placeText: string;
        if (rawPlace.length > 0) {
          placeText = rawPlace;
        } else if (hasPoll) {
          placeText = "장소 투표 중";
        } else {
          placeText = "장소 미정";
        }

        await sendMulticastAndCleanup(
          tokens,
          {
            notification: {
              title: "오늘 가족 모임이 있어요!",
              body: `${familyName} 모임이 있어요 — ${placeText}`,
            },
          },
          `DDay[${familyDoc.id}/${meetingDoc.id}]`
        );
      }
    }
  }
);

// ============================================================
// 4d. 콕 찌르기 알림 — Firestore Trigger
// ============================================================
// 참석 미정인 멤버를 누군가 "콕 찌르면" nudges 문서가 생기고,
// 대상 멤버에게만 푸시. 푸시 탭 시 해당 모임 상세로 deep-link.
export const onNudgeCreated = onDocumentCreated(
  "families/{familyId}/meetings/{meetingId}/nudges/{nudgeId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const nudge = snapshot.data();
    const familyId = event.params.familyId;
    const meetingId = event.params.meetingId;

    const targetUserId = nudge.targetUserId as string | undefined;
    const fromName = (nudge.fromName as string | undefined) || "누군가";
    if (!targetUserId) return;

    // 3시간 쿨다운: 같은 모임·같은 대상에 최근 3시간 내 찌른 적이 있으면
    // 푸시 스킵. 연타나 여러 가족의 중복 찌르기로 인한 알림 폭탄 방지.
    // (equality-only 쿼리라 단일 필드 인덱스로 충분 — 복합 인덱스 불필요)
    const COOLDOWN_MS = 3 * 60 * 60 * 1000;
    const nudgeId = event.params.nudgeId;
    const createdAtMs =
      (nudge.createdAt as Timestamp | undefined)?.toMillis() ?? Date.now();
    const priorSnap = await db
      .collection("families").doc(familyId)
      .collection("meetings").doc(meetingId)
      .collection("nudges")
      .where("targetUserId", "==", targetUserId)
      .get();
    const hasRecent = priorSnap.docs.some((d) => {
      if (d.id === nudgeId) return false;
      const t =
        (d.data().createdAt as Timestamp | undefined)?.toMillis() ?? 0;
      return t >= createdAtMs - COOLDOWN_MS;
    });
    if (hasRecent) {
      console.log(
        `Nudge cooldown: skip ${targetUserId} ` +
        `in ${familyId}/${meetingId} (within 3h)`
      );
      return;
    }

    const userDoc = await db
      .collection("users").doc(targetUserId).get();
    const userData = userDoc.data();
    const userTokens = deviceTokens(userData);
    const notificationsEnabled =
      userData?.notificationsEnabled !== false;
    const notifyNudge =
      userData?.notifyNudge !== false;
    if (userTokens.length === 0) return;
    if (!notificationsEnabled || !notifyNudge) return;

    // 모임 장소 (후보 모드면 fallback)
    let meetingContext = "이번 모임";
    try {
      const meetingDoc = await db
        .collection("families").doc(familyId)
        .collection("meetings").doc(meetingId)
        .get();
      const place = meetingDoc.data()?.place as string | undefined;
      if (place && place.length > 0) meetingContext = place;
      else if (meetingDoc.data()?.hasPoll) {
        meetingContext = "장소 투표 중인 모임";
      }
    } catch (e) {
      console.error("Meeting fetch failed:", e);
    }

    for (const token of userTokens) {
      try {
        await getMessaging().send({
          notification: {
            title: `${fromName}님이 콕 찔렀어요`,
            body: `${meetingContext} 참석 여부를 알려주세요.`,
          },
          data: {
            type: "meetingAttendance",
            meetingId,
          },
          token,
        });
        console.log(`Nudge: ${targetUserId} in ${familyId}/${meetingId}`);
      } catch (error) {
        const code = (error as {code?: string})?.code;
        console.error(`Nudge error (${targetUserId}): code=${code}`, error);
        if (code && STALE_TOKEN_CODES.has(code)) {
          await cleanupInvalidTokens([token]);
        }
      }
    }
  }
);

// ============================================================
// 5. 고아 가정 정리 — 매주 월요일 새벽 3시 (KST)
// ============================================================
// 멤버 0명이거나, 모든 멤버의 users 문서가 사라진 가정은
// 재접속 경로가 없으므로 cascade 삭제한다.
// createdAt 7일 이상 지난 가정만 대상으로 해서 생성 직후 race 상태를 피함.
export const cleanupOrphanFamilies = onSchedule(
  {schedule: "0 3 * * 1", timeZone: "Asia/Seoul"},
  async () => {
    const cutoff = Timestamp.fromDate(
      new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
    );
    const families = await db.collection("families").get();
    let deleted = 0;
    for (const famDoc of families.docs) {
      const createdAt = famDoc.data().createdAt as Timestamp | undefined;
      if (createdAt && createdAt.toMillis() > cutoff.toMillis()) continue;

      const membersSnap = await famDoc.ref.collection("members").get();
      let orphan = membersSnap.empty;
      if (!orphan) {
        orphan = true;
        for (const m of membersSnap.docs) {
          const u = await db.collection("users").doc(m.id).get();
          if (u.exists) {
            orphan = false;
            break;
          }
        }
      }
      if (!orphan) continue;

      try {
        await db.recursiveDelete(famDoc.ref);
        deleted++;
        console.log(`Orphan family deleted: ${famDoc.id}`);
      } catch (e) {
        console.error(`Failed to delete ${famDoc.id}:`, e);
      }
    }
    console.log(`Orphan cleanup done: ${deleted} deleted`);
  }
);

// ============================================================
// Helper
// ============================================================

/**
 * FCM이 invalid/unregistered로 답한 토큰으로 간주하는 에러 코드 집합.
 * 이 코드가 오면 해당 기기는 더 이상 푸시를 받을 수 없으므로
 * Firestore에서 fcmToken 필드를 제거해 다음 발송 시 낭비를 막는다.
 */
const STALE_TOKEN_CODES = new Set<string>([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

/**
 * 유저의 기기 토큰을 모두 수집 — iOS(fcmToken) + 웹(webFcmToken).
 * 웹은 iOS와 다른 필드를 쓰므로 양쪽 모두에게 발송해야 한다.
 * @param {object|undefined} userData users 문서 데이터
 * @return {string[]} 유효한 토큰 배열
 */
function deviceTokens(
  userData: FirebaseFirestore.DocumentData | undefined
): string[] {
  return [userData?.fcmToken, userData?.webFcmToken]
    .filter((t): t is string => typeof t === "string" && t.length > 0);
}

/**
 * 주어진 토큰들을 가진 users 문서에서 fcmToken 필드를 제거.
 * @param {string[]} tokens 무효로 판정된 토큰들
 */
async function cleanupInvalidTokens(tokens: string[]): Promise<void> {
  for (const token of tokens) {
    for (const field of ["fcmToken", "webFcmToken"]) {
      const snap = await db.collection("users")
        .where(field, "==", token).get();
      for (const doc of snap.docs) {
        try {
          await doc.ref.update({[field]: FieldValue.delete()});
          console.log(`Cleared stale ${field} from user ${doc.id}`);
        } catch (e) {
          console.error(`Failed to clear token for ${doc.id}:`, e);
        }
      }
    }
  }
}

/**
 * 멀티캐스트 푸시를 보내고, 무효 토큰은 Firestore에서 자동 정리한다.
 * @param {string[]} tokens 대상 FCM 토큰
 * @param {object} payload notification payload (title/body 포함, 선택적 data)
 * @param {string} label 로그 prefix
 */
async function sendMulticastAndCleanup(
  tokens: string[],
  payload: {
    notification: {title: string; body: string};
    data?: Record<string, string>;
  },
  label: string
): Promise<void> {
  if (tokens.length === 0) return;
  try {
    const response = await getMessaging()
      .sendEachForMulticast({...payload, tokens});
    console.log(
      `${label}: ${response.successCount} ok, ` +
      `${response.failureCount} fail`
    );
    const invalidTokens: string[] = [];
    response.responses.forEach((r, i) => {
      if (!r.success) {
        const code = r.error?.code;
        console.error(
          `Failed token[${i}] ${tokens[i].substring(0, 20)}...: ` +
          `code=${code} msg=${r.error?.message}`
        );
        if (code && STALE_TOKEN_CODES.has(code)) {
          invalidTokens.push(tokens[i]);
        }
      }
    });
    if (invalidTokens.length > 0) {
      await cleanupInvalidTokens(invalidTokens);
    }
  } catch (error) {
    console.error(`${label} error:`, error);
  }
}

/**
 * 이번 주 월요일 00:00 KST를 UTC Date로 반환.
 * Cloud Functions 런타임이 UTC라서 getDay/getDate를 그대로 쓰면
 * KST 기준 주 경계가 9시간 밀린다. KST 벽시계 기준으로 계산한 뒤
 * -9h 해서 UTC Date로 돌려준다.
 * @param {Date} date 기준 시각 (UTC)
 * @return {Date} 이번 주 월요일 00:00 KST에 해당하는 UTC Date
 */
function getStartOfWeek(date: Date): Date {
  const kst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
  const kstDay = kst.getUTCDay();
  const diff = kstDay === 0 ? -6 : 1 - kstDay;
  const mondayKst = new Date(kst);
  mondayKst.setUTCDate(kst.getUTCDate() + diff);
  mondayKst.setUTCHours(0, 0, 0, 0);
  return new Date(mondayKst.getTime() - 9 * 60 * 60 * 1000);
}
