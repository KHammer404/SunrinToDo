# SunrinToDo

선린인터넷고등학교 학생용 Flutter 앱입니다. 시간표, 급식, 학급 캘린더, 학사일정을 한 곳에서 확인하는 것을 목표로 합니다.

## 현재 구현 범위

- Google 로그인과 학교 도메인 제한
- 시간표 조회 및 날짜/교시별 개인 과목명 수정
- 급식 조회
- 학사일정 조회
- 개인/학급 캘린더 일정 조회, 생성, 수정, 삭제
- 학급 생성, 초대 코드/링크 참여, 멤버 목록, 색상 변경, 나가기/삭제 정책
- 알림 기본 설정 저장 및 FCM 토큰 동기화
- Firestore Rules 및 에뮬레이터 기반 Rules 테스트

## 환경 요구사항

- Flutter 3.41.x
- Dart 3.11.x
- Node.js 20
- Firebase CLI
- Java 21+ 또는 현재 설치된 호환 JDK

## 필수 설정

### 1. Firebase 설정

이 공개 저장소에는 실제 Firebase 프로젝트 키를 커밋하지 않습니다. 실행 전 본인 Firebase 프로젝트로 FlutterFire 설정을 생성하세요.

- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`
- Dart: `lib/firebase_options.dart`

권장 방식:

```bash
flutterfire configure
```

현재 `lib/firebase_options.dart` 는 공개 저장소용 템플릿입니다. `flutterfire configure` 로 교체하거나, 파일에 적힌 `--dart-define` 값들을 직접 주입해야 앱이 Firebase를 초기화할 수 있습니다.

로컬 전용 값은 커밋하지 않는 `firebase_dart_defines.local.json` 에 둘 수 있습니다.

### 2. NEIS API 키

NEIS 키는 저장소에 커밋하지 않고 `--dart-define` 으로 주입합니다.

필수 환경값:

- `NEIS_API_KEY`

키가 없으면 시간표/급식 화면은 설정 안내 메시지를 표시합니다.
학사일정 화면은 학교 정적 일정은 계속 보이고, NEIS 보완 일정만 빠집니다.

## 실행 방법

Android 또는 연결된 기본 기기에서 실행:

```bash
flutter run --dart-define=NEIS_API_KEY=YOUR_NEIS_API_KEY
```

로컬 Firebase define 파일을 쓰는 경우:

```bash
flutter run \
  --dart-define-from-file=firebase_dart_defines.local.json \
  --dart-define=NEIS_API_KEY=YOUR_NEIS_API_KEY
```

특정 기기 지정:

```bash
flutter run -d emulator-5554 --dart-define=NEIS_API_KEY=YOUR_NEIS_API_KEY
```

APK 빌드:

```bash
flutter build apk --debug --dart-define=NEIS_API_KEY=YOUR_NEIS_API_KEY
```

iOS 빌드:

```bash
flutter build ios --dart-define=NEIS_API_KEY=YOUR_NEIS_API_KEY
```

## 개발 순서 권장

1. Flutter 의존성 설치: `flutter pub get`
2. Firebase CLI 로그인 확인
3. NEIS 키 준비
4. `flutter run --dart-define=NEIS_API_KEY=...`
5. Firestore Rules를 수정했다면 실행 전에 `npm run test:rules` 로 검증

## 전체 검증

공개 저장소 기준 전체 검증은 다음 명령을 사용합니다.

```bash
flutter analyze
flutter test
npm --prefix functions run lint
npm run test:rules
```

`npm run test:rules` 는 Firestore Emulator가 필요합니다.

## Firestore Rules 테스트

Rules 테스트는 Firestore Emulator와 공식 테스트 라이브러리로 실행합니다.

의존성 설치:

```bash
npm install
```

테스트 실행:

```bash
npm run test:rules
```

현재 포함된 테스트 시나리오:

- 학급 멤버 전용 읽기
- 비멤버 초대 코드 최소 문서 조회
- 학급/초대 문서 batch 생성 및 초대 코드 중복 방지
- 자기 자신만 학급 참여 가능
- 타인 UID 동반 참여 거부
- 일반 멤버 탈퇴와 방장 탈퇴 제한
- 방장 학급 색상 변경 권한
- 개인 일정 `memberIds` 제한
- 학급 일정 멤버 스냅샷 검증
- 개인/학급 일정 수정 권한 검증
- 개인/학급 일정 삭제 권한 검증
- 알림 문서 `userId` 소유권 검증
- 시간표 개인 수정 문서 소유권과 교시별 override/reset 검증

## 시간표 개인 수정

시간표 원본은 NEIS 데이터를 유지하고, 사용자가 바꾼 과목명만 개인 Firestore 문서에 저장합니다.

- 저장 위치: `users/{uid}/timetableOverrides/{yyyyMMdd}`
- 저장 단위: 날짜별 문서 안의 `periods.{period}` 과목명 override
- 표시 규칙: NEIS 시간표를 먼저 불러온 뒤 개인 override를 적용
- 초기화 규칙: 교시별 `원래대로` 는 해당 period override를 삭제하고, 날짜 전체 초기화는 날짜 문서를 삭제
- 빈칸 저장: 빈 과목명도 명시적인 override로 저장하며 reset과 구분

시간표 화면과 캘린더 선택 날짜 패널은 같은 merge helper를 사용해 동일한 과목명을 표시합니다.

## 알림 백엔드

앱은 현재 다음 데이터를 Firestore에 동기화합니다.

- `users/{uid}`: FCM 토큰, 시스템 알림 권한 상태, 앱 내 알림 기본 설정
- `events/{eventId}`: 일정 생성/수정/삭제. 기본 일정 알림 문서는 서버 스케줄러가 upcoming events를 주기적으로 스캔해 생성합니다.

알림 발송은 기본적으로 GitHub Actions schedule workflow가 담당합니다. Firebase Functions 배포 없이도 15분마다 같은 Node dispatcher를 실행합니다.

- `.github/workflows/dispatch-notifications.yml`: 15분마다 실행되는 GitHub Actions workflow
- `functions/scripts/dispatch-notifications.js`: GitHub Actions에서 실행하는 엔트리포인트
- `functions/notification_dispatcher.js`: Functions wrapper와 GitHub Actions가 공유하는 알림 dispatcher
- `syncUpcomingEventNotifications`: upcoming events를 스캔해 미발송 알림 예약 문서 갱신
- `dispatchScheduledNotifications`: 예약 시간이 지난 알림을 FCM으로 발송
- `dispatchMealNotifications`: 사용자별 설정 시간에 NEIS 중식 정보를 FCM으로 발송

알림을 눌렀을 때 앱 이동 경로:

- 일정 알림(`event_default`): 캘린더
- 급식 알림(`meal`): 급식 화면
- 알 수 없는 알림 타입: 캘린더

Functions 의존성 설치:

```bash
cd functions
npm install
```

로컬에서 알림 dispatcher를 직접 실행:

```bash
cd functions
FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID \
FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account", ...}' \
NEIS_API_KEY=YOUR_NEIS_API_KEY \
npm run dispatch:notifications
```

`FIREBASE_SERVICE_ACCOUNT_JSON` 은 raw JSON 또는 base64 인코딩 JSON을 모두 허용합니다. 로컬 Application Default Credentials를 설정해 둔 환경에서는 생략할 수 있습니다.

GitHub Actions에서 알림을 사용하려면 repository variables/secrets에 다음 값을 설정합니다.

- repository variable `FIREBASE_PROJECT_ID`: Firebase project id
- `FIREBASE_SERVICE_ACCOUNT_JSON`: Firebase Admin SDK 서비스 계정 JSON
- `NEIS_API_KEY`: 급식 조회용 NEIS API 키

workflow는 `schedule`과 `workflow_dispatch`를 모두 지원하므로 GitHub Actions 탭에서 수동 실행할 수 있습니다.

Firestore Rules 배포:

```bash
firebase deploy --project YOUR_FIREBASE_PROJECT_ID --only firestore
```

Firebase Functions wrapper는 `functions/index.js`에 남겨 두었지만 기본 운영 경로는 GitHub Actions입니다. Functions까지 배포하려면 Firebase Blaze 플랜이 필요합니다.

## 주요 경로

- 앱 진입점: `lib/main.dart`
- 라우팅: `lib/core/router/app_router.dart`
- NEIS 연동: `lib/core/services/neis_service.dart`
- 시간표 개인 수정 저장: `lib/core/services/timetable_override_service.dart`
- 시간표 표시 merge: `lib/core/services/timetable_merge_service.dart`
- 학사일정 화면: `lib/features/schedule/schedule_screen.dart`
- 시간표: `lib/features/timetable/timetable_screen.dart`
- 캘린더: `lib/features/calendar/`
- 학급: `lib/features/class/`
- Firestore Rules: `firestore.rules`
- Rules 테스트: `firestore.rules.test.cjs`
- Firestore 인덱스: `firestore.indexes.json`
- 알림 dispatcher: `functions/notification_dispatcher.js`
- GitHub Actions 알림 workflow: `.github/workflows/dispatch-notifications.yml`
- 선택적 Functions wrapper: `functions/index.js`

## 주의사항

- `NEIS_API_KEY` 없이 빌드하면 시간표/급식은 조회할 수 없고, 학사일정은 학교 정적 일정만 표시됩니다.
- 학사일정은 학교 PDF 기준 `lib/core/data/school_events_2026.dart` 를 우선 사용합니다.
- 시간표 개인 수정은 로그인 사용자별 데이터이며 NEIS 원본 자체를 변경하지 않습니다.
- 현재 정적 학사일정 데이터는 2026학년도만 포함합니다. 학년도 말 일정 때문에 2027년 2월 일부 날짜가 포함되어 있습니다. 2027학년도 학사일정은 내년에 학교 자료가 공개된 뒤 필요할 때 추가합니다.
- NEIS `SchoolSchedule` 일정은 로컬 일정이 없는 날짜만 보완용으로 표시합니다.
- 위 정책은 학교 PDF와 NEIS 학사일정 값이 서로 다를 수 있다는 운영 이유를 반영합니다.
- 실제 푸시 알림 발송은 GitHub Actions secrets 설정 후 workflow가 실행되어야 동작합니다.
- GitHub Actions schedule은 UTC 기준이며, 실행 시각은 GitHub 부하에 따라 지연될 수 있습니다.
- Firestore Rules 변경 후에는 `npm run test:rules` 로 먼저 검증하는 것을 권장합니다.
- 기존 운영 학급 문서가 있다면 새 초대 참여 구조에 맞춰 `classInvites/{code}` 문서를 함께 준비해야 합니다.
