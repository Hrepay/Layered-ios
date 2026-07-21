// Firestore·Storage 보안 규칙 유닛 테스트
// 실행: rules-tests/ 에서 `npm test` — 로컬 에뮬레이터에서만 동작, 프로덕션에 접근하지 않음.
//
// 시나리오는 클라이언트 코드가 실제로 수행하는 쓰기 형태를 그대로 재현한다:
// - 가입: FirebaseFamilyRepository.joinFamily 트랜잭션 (member set + memberCount+1 + users update)
// - 강퇴: FirebaseMemberRepository.removeMember batch
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc,
  collection, writeBatch, deleteField, Timestamp,
} from 'firebase/firestore';
import { ref as storageRef, uploadBytes } from 'firebase/storage';

const here = dirname(fileURLToPath(import.meta.url));
let testEnv;

const FUTURE = Timestamp.fromMillis(Date.now() + 30 * 60 * 1000);
const PAST = Timestamp.fromMillis(Date.now() - 60 * 1000);

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-layered',
    firestore: { rules: readFileSync(join(here, '../firestore.rules'), 'utf8') },
    storage: { rules: readFileSync(join(here, '../storage.rules'), 'utf8') },
  });
});

after(async () => {
  await testEnv.cleanup();
});

// 시드: 가족 F1 (관리자 alice, 멤버 bob, 코드 CODE01 유효) / 가족 F2 (코드 만료)
beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'families/F1'), {
      name: '황씨네', adminId: 'alice', inviteCode: 'CODE01',
      inviteCodeExpiresAt: FUTURE, memberCount: 2,
      currentPlannerIndex: 0, rotationDay: 1, rotationMode: 'auto', createdAt: PAST,
    });
    await setDoc(doc(db, 'families/F1/members/alice'), { name: '앨리스', role: 'admin', rotationOrder: 0, joinedAt: PAST });
    await setDoc(doc(db, 'families/F1/members/bob'), { name: '밥', role: 'member', rotationOrder: 1, joinedAt: PAST });
    await setDoc(doc(db, 'users/alice'), { name: '앨리스', familyId: 'F1', fcmToken: 'tok-a' });
    await setDoc(doc(db, 'users/bob'), { name: '밥', familyId: 'F1', fcmToken: 'tok-b' });
    await setDoc(doc(db, 'users/carol'), { name: '캐롤' });
    await setDoc(doc(db, 'inviteCodes/CODE01'), { familyId: 'F1', expiresAt: FUTURE, createdAt: PAST });

    await setDoc(doc(db, 'families/F2'), {
      name: '만료가정', adminId: 'dave', inviteCode: 'OLD999',
      inviteCodeExpiresAt: PAST, memberCount: 1,
      currentPlannerIndex: 0, rotationDay: 1, rotationMode: 'auto', createdAt: PAST,
    });
    await setDoc(doc(db, 'families/F1/meetings/m1'), {
      plannerId: 'alice', plannerName: '앨리스', meetingDate: FUTURE,
      place: '집', status: 'planning', hasPoll: false, createdAt: PAST, updatedAt: PAST,
    });
    await setDoc(doc(db, 'families/F1/meetings/m1/records/r1'), {
      memberId: 'bob', memberName: '밥', rating: 5, comment: '좋았다', photos: [], createdAt: PAST,
    });
  });
});

const db = (uid) => (uid ? testEnv.authenticatedContext(uid) : testEnv.unauthenticatedContext()).firestore();

// ───────────────────────── 가입 (초대 코드 검증)

test('무단 가입 차단: 코드 없이 멤버 문서 생성 → 거부', async () => {
  await assertFails(setDoc(doc(db('carol'), 'families/F1/members/carol'), {
    name: '캐롤', role: 'member', rotationOrder: 2, joinedAt: FUTURE,
  }));
});

test('정상 가입: 올바른 joinCode + 멤버 생성/카운트+1 원자 쓰기 → 허용', async () => {
  const carol = db('carol');
  const batch = writeBatch(carol);
  batch.set(doc(carol, 'families/F1/members/carol'), {
    name: '캐롤', role: 'member', rotationOrder: 2, joinCode: 'CODE01', joinedAt: FUTURE,
  });
  batch.update(doc(carol, 'families/F1'), { memberCount: 3 });
  batch.update(doc(carol, 'users/carol'), { familyId: 'F1' });
  await assertSucceeds(batch.commit());
});

test('틀린 joinCode → 거부', async () => {
  await assertFails(setDoc(doc(db('carol'), 'families/F1/members/carol'), {
    name: '캐롤', role: 'member', rotationOrder: 2, joinCode: 'WRONG1', joinedAt: FUTURE,
  }));
});

test('만료된 코드로 가입 → 거부', async () => {
  await assertFails(setDoc(doc(db('carol'), 'families/F2/members/carol'), {
    name: '캐롤', role: 'member', rotationOrder: 1, joinCode: 'OLD999', joinedAt: FUTURE,
  }));
});

test('가입 시 role: admin 으로 생성 시도 → 거부', async () => {
  await assertFails(setDoc(doc(db('carol'), 'families/F1/members/carol'), {
    name: '캐롤', role: 'admin', rotationOrder: 2, joinCode: 'CODE01', joinedAt: FUTURE,
  }));
});

test('가정 생성자 흐름: adminId 본인인 가정에 admin 멤버 생성 → 허용', async () => {
  const carol = db('carol');
  await assertSucceeds(setDoc(doc(carol, 'families/F3'), {
    name: '새가정', adminId: 'carol', inviteCode: 'NEW111',
    inviteCodeExpiresAt: FUTURE, memberCount: 1,
    currentPlannerIndex: 0, rotationDay: 1, rotationMode: 'auto', createdAt: FUTURE,
  }));
  await assertSucceeds(setDoc(doc(carol, 'families/F3/members/carol'), {
    name: '캐롤', role: 'admin', rotationOrder: 0, joinedAt: FUTURE,
  }));
});

// ───────────────────────── 권한 상승 차단

test('일반 멤버가 자기 role을 admin으로 변경 → 거부', async () => {
  await assertFails(updateDoc(doc(db('bob'), 'families/F1/members/bob'), { role: 'admin' }));
});

test('일반 멤버가 role 유지한 채 이름 변경 → 허용', async () => {
  await assertSucceeds(updateDoc(doc(db('bob'), 'families/F1/members/bob'), { name: '밥2', role: 'member' }));
});

test('관리자가 다른 멤버 role 변경(위임) → 허용', async () => {
  await assertSucceeds(updateDoc(doc(db('alice'), 'families/F1/members/bob'), { role: 'admin' }));
});

test('일반 멤버가 families.adminId 탈취 → 거부', async () => {
  await assertFails(updateDoc(doc(db('bob'), 'families/F1'), { adminId: 'bob' }));
});

test('일반 멤버의 운영 필드(currentPlannerIndex) 변경 → 허용', async () => {
  await assertSucceeds(updateDoc(doc(db('bob'), 'families/F1'), { currentPlannerIndex: 1 }));
});

// ───────────────────────── 열거·노출 차단

test('families 컬렉션 list(초대코드 수집) → 거부', async () => {
  await assertFails(getDocs(collection(db('carol'), 'families')));
});

test('families 단건 get (ID를 아는 경우) → 허용', async () => {
  await assertSucceeds(getDoc(doc(db('carol'), 'families/F1')));
});

test('inviteCodes: 코드를 아는 사람의 get 허용, list 거부', async () => {
  await assertSucceeds(getDoc(doc(db('carol'), 'inviteCodes/CODE01')));
  await assertFails(getDocs(collection(db('carol'), 'inviteCodes')));
});

test('users: 타 가족(carol)이 alice 문서 읽기 → 거부', async () => {
  await assertFails(getDoc(doc(db('carol'), 'users/alice')));
});

test('users: 같은 가족(bob)이 alice 문서 읽기 → 허용', async () => {
  await assertSucceeds(getDoc(doc(db('bob'), 'users/alice')));
});

test('비로그인 사용자의 family 읽기 → 거부', async () => {
  await assertFails(getDoc(doc(db(null), 'families/F1')));
});

// ───────────────────────── 강퇴 (removeMember batch)

test('관리자 강퇴 batch: 카운트-1 + 멤버 삭제 + familyId 해제 → 허용', async () => {
  const alice = db('alice');
  const batch = writeBatch(alice);
  batch.update(doc(alice, 'families/F1'), { memberCount: 1 });
  batch.delete(doc(alice, 'families/F1/members/bob'));
  batch.update(doc(alice, 'users/bob'), { familyId: deleteField() });
  await assertSucceeds(batch.commit());
});

test('일반 멤버가 남의 users 문서 수정 → 거부', async () => {
  await assertFails(updateDoc(doc(db('bob'), 'users/alice'), { familyId: deleteField() }));
});

test('일반 멤버가 다른 멤버 강퇴(멤버 문서 삭제) → 거부', async () => {
  await assertFails(deleteDoc(doc(db('bob'), 'families/F1/members/alice')));
});

// ───────────────────────── 데이터 위조 차단

test('기록 소유자 재할당(memberId 변경) → 거부', async () => {
  await assertFails(updateDoc(doc(db('bob'), 'families/F1/meetings/m1/records/r1'), { memberId: 'alice' }));
});

test('기록 본인 수정(memberId 유지) → 허용', async () => {
  await assertSucceeds(updateDoc(doc(db('bob'), 'families/F1/meetings/m1/records/r1'), { comment: '수정' }));
});

test('모임 수정자 표기 위조(lastEditedById 타인) → 거부', async () => {
  await assertFails(updateDoc(doc(db('bob'), 'families/F1/meetings/m1'), {
    place: '카페', lastEditedById: 'alice', lastEditedByName: '앨리스',
  }));
});

test('모임 수정자 표기 본인 → 허용', async () => {
  await assertSucceeds(updateDoc(doc(db('bob'), 'families/F1/meetings/m1'), {
    place: '카페', lastEditedById: 'bob', lastEditedByName: '밥',
  }));
});

// ───────────────────────── 가족 맛집 리스트 (placeWishes)

test('맛집 추천: 멤버가 본인 recommenderId로 생성 → 허용', async () => {
  await assertSucceeds(setDoc(doc(db('bob'), 'families/F1/placeWishes/w1'), {
    placeId: 'k1', name: '서관면옥', category: '냉면', address: '서초구',
    latitude: 37.5, longitude: 127.0, recommenderId: 'bob', recommenderName: '밥',
    status: 'wishlist', createdAt: FUTURE,
  }));
});

test('맛집 추천: 추천자 위조(recommenderId 타인) → 거부', async () => {
  await assertFails(setDoc(doc(db('bob'), 'families/F1/placeWishes/w2'), {
    placeId: 'k2', name: '위조', category: '한식', address: '서초구',
    latitude: 37.5, longitude: 127.0, recommenderId: 'alice', recommenderName: '앨리스',
    status: 'wishlist', createdAt: FUTURE,
  }));
});

test('맛집 추천: 비멤버 읽기/생성 → 거부', async () => {
  await assertFails(getDocs(collection(db('carol'), 'families/F1/placeWishes')));
  await assertFails(setDoc(doc(db('carol'), 'families/F1/placeWishes/w3'), {
    placeId: 'k3', name: '외부인', category: '한식', address: '서초구',
    latitude: 37.5, longitude: 127.0, recommenderId: 'carol', recommenderName: '캐롤',
    status: 'wishlist', createdAt: FUTURE,
  }));
});

// ───────────────────────── Storage (가족 사진 경로 멤버십)

test('Storage: 비멤버(carol)의 노트 사진 업로드 → 거부', async () => {
  const storage = testEnv.authenticatedContext('carol').storage();
  await assertFails(uploadBytes(
    storageRef(storage, 'families/F1/notes/n1/photo.jpg'),
    new Uint8Array([0xff, 0xd8, 0xff]), { contentType: 'image/jpeg' },
  ));
});

test('Storage: 멤버(bob)의 노트 사진 업로드 → 허용', async () => {
  const storage = testEnv.authenticatedContext('bob').storage();
  await assertSucceeds(uploadBytes(
    storageRef(storage, 'families/F1/notes/n1/photo.jpg'),
    new Uint8Array([0xff, 0xd8, 0xff]), { contentType: 'image/jpeg' },
  ));
});

test('Storage: 멤버라도 이미지 아닌 파일 → 거부', async () => {
  const storage = testEnv.authenticatedContext('bob').storage();
  await assertFails(uploadBytes(
    storageRef(storage, 'families/F1/notes/n1/note.txt'),
    new Uint8Array([1, 2, 3]), { contentType: 'text/plain' },
  ));
});
