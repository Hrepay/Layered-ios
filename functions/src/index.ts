import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {setGlobalOptions} from "firebase-functions/v2";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
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
      const fcmToken = userData?.fcmToken;
      const notificationsEnabled =
        userData?.notificationsEnabled !== false;
      const notifyMeetingCreated =
        userData?.notifyMeetingCreated !== false;
      if (fcmToken && notificationsEnabled && notifyMeetingCreated) {
        tokens.push(fcmToken);
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
    const message = {
      notification: {
        title: `${planner}님이 가족 모임을 등록했어요!`,
        body: `${place}${dateStr}`,
      },
      tokens: tokens,
    };

    try {
      const response = await getMessaging()
        .sendEachForMulticast(message);
      console.log(
        `Notification: ${response.successCount} ok, ` +
        `${response.failureCount} fail`
      );
      response.responses.forEach((r, i) => {
        if (!r.success) {
          console.error(
            `Failed token[${i}] ${tokens[i].substring(0, 20)}...: ` +
            `code=${r.error?.code} msg=${r.error?.message}`
          );
        }
      });
    } catch (error) {
      console.error("Notification error:", error);
    }
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
      const fcmToken = userData?.fcmToken;
      const notificationsEnabled =
        userData?.notificationsEnabled !== false;
      const notifyPlannerReminder =
        userData?.notifyPlannerReminder !== false;

      if (!fcmToken) continue;
      if (!notificationsEnabled || !notifyPlannerReminder) continue;

      const familyName = data.name || "가정";
      try {
        await getMessaging().send({
          notification: {
            title: "이번 주 모임을 계획해주세요!",
            body: `${familyName}의 플래너로 지정되었어요.`,
          },
          token: fcmToken,
        });
        console.log(
          `Reminder: ${plannerDoc.id} in ${familyDoc.id}`
        );
      } catch (error) {
        console.error("Reminder error:", error);
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
