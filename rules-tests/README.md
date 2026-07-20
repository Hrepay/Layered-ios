# 보안 규칙 유닛 테스트

`firestore.rules` / `storage.rules`를 로컬 에뮬레이터에서 검증한다. **프로덕션에 접근하지 않는다.**

```bash
cd rules-tests
npm install          # 최초 1회
npm test
```

- Firebase 에뮬레이터는 **JDK 21 이상**이 필요. 시스템 기본이 낮으면:
  ```bash
  export JAVA_HOME=/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home
  ```
- 규칙을 수정하면 배포 전에 반드시 이 테스트를 돌려서 가입·강퇴·권한 상승 차단이 유지되는지 확인한다.
- 시나리오는 클라이언트 실제 쓰기 형태를 재현한다: 가입 트랜잭션(`joinFamily`), 강퇴 batch(`removeMember`), Storage 교차 멤버십 확인 등 27케이스.
