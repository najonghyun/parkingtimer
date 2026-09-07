# <img src="store/assets/icon_512.png" height="25px"> **차빼요 — 주차 시간 알림** &nbsp; <img src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=Flutter&logoColor=white"/> <img src="https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=Dart&logoColor=white"/> <img src="https://img.shields.io/badge/Firebase-DD2C00?style=flat-square&logo=Firebase&logoColor=white"/> <img src="https://img.shields.io/badge/Cloudflare%20Workers-F38020?style=flat-square&logo=Cloudflare&logoColor=white"/> <img src="https://img.shields.io/badge/TypeScript-3178C6?style=flat-square&logo=TypeScript&logoColor=white"/>

#### 주차 제한 시간이 끝나기 전에 확실하게 알려주는, 버튼 하나짜리 모바일 앱입니다.

#### 기획부터 구현·배포까지 **Claude Code를 활용해 진행한 AI 활용 프로젝트**입니다.

### https://parking-timer-worker.i0364842-757.workers.dev/privacy

---

### 모바일(Android · iOS) / 개인 프로젝트

### 2026.08.01 ~ 2026.08.03 (Play 스토어 출시 준비)

> **앱 기획·UI 구현·알림 인프라(Firebase + Cloudflare Worker) 구축·스토어 출시 준비 전 과정 단독 진행**

---

### 💻 Overview

<img src="store/assets/feature_graphic_1024x500.png" width="100%">

<br>
<br>

| **Main** — 남은 시간 · 단계 표시 · 주차 기록 | **Settings** — 제한 시간 선택 · 알림 정책 |
|:---:|:---:|
| <img src="store/assets/screenshot_1_timer.png" width="330"> | <img src="store/assets/screenshot_2_settings.png" width="330"> |
| 원형 게이지가 남은 시간을 보여주고, 가운데 배지가<br>`안전 → 주의 → 위험 → 초과` 단계를 색으로 알립니다.<br>버튼 하나로 타이머를 시작하고, 오늘 주차 횟수와<br>최근 기록이 아래에 바로 쌓입니다. | 같은 화면을 아래로 내리면 제한 시간을<br>**1 / 2 / 3시간** 중에 탭 한 번으로 바꿀 수 있고,<br>지금 설정에서 알림이 언제 울리는지<br>문장으로 그대로 확인할 수 있습니다. |

<br>

---

### 💡 기획

마트나 카페의 무료 주차 시간을 깜빡해서 과태료를 내는 일이 잦다는 데서 출발했습니다.
비슷한 앱들은 대부분 차량 등록·위치 저장·메모까지 요구하는데, 정작 필요한 건
**"주차했다"는 사실 하나와 제때 오는 알림**뿐이라고 봤습니다. 그래서 회원가입도 설정도
없이 **버튼 한 번으로 끝나는 최소 기능**만 남겼습니다.

개발 과정 전체를 Claude Code와 함께 진행했습니다. 단순 코드 생성이 아니라, 실기기에서
알림이 죽는 원인을 `dumpsys notification`으로 함께 추적하고, 무료 플랜 제약 안에서
서버 구조를 다시 설계하는 등 **문제 진단과 아키텍처 의사결정 단계에서 AI를 활용**했습니다.
아래 '알림이 죽는 문제' 항목이 그 과정에서 나온 결론입니다.

<br>

### 🖇️ 기능

> ### ☝️ One Tap

- 주차한 순간 '주차했어요' 버튼 하나만 누르면 됩니다. 입력할 것도, 로그인도 없습니다.
- 마감 시각이 지나면 알림 없이 타이머가 자동으로 리셋됩니다.

> ### ⏱️ Timer Ring

- 남은 시간을 원형 게이지로 표시하고, 진행 상태에 따라 색이 단계별로 변합니다.
- `안전(초록) → 주의(주황) → 위험(빨강) → 초과(진빨강)` 4단계.

> ### 🔔 Alert

- 마감 **30분 전**(경고) · **10분 전**(위험) · **7분 전**(마지막 경고) 총 3회 알림.
- 위험 알림은 진한 빨간색으로 알림창에 남아, 나중에 봐도 미처리 상태임을 알 수 있습니다.

> ### 🅿️ Limit

- 마트는 2시간, 카페는 1시간처럼 장소마다 다른 제한을 **1 / 2 / 3시간** 중에 탭 한 번으로 변경.
- 어떤 시간을 골라도 '30분 전 · 10분 전'이라는 알림 기준은 동일하게 유지됩니다.

> ### 📊 History

- 오늘 주차 횟수와 최근 기록을 홈 화면에서 바로 확인할 수 있습니다.
- 기록은 기기에만 저장되며 매일 자정에 카운터가 초기화됩니다.

<br>

---

### 🧩 알림이 죽는 문제, 그리고 플랫폼별로 갈라진 구조

이 프로젝트에서 가장 많은 시간을 쓴 부분입니다.

처음에는 양쪽 다 로컬 알림(`flutter_local_notifications` + `AlarmManager`)이었습니다.
그런데 **삼성 등 OEM의 '백그라운드 사용 제한'에 걸리면 예약된 로컬 알람이 조용히
죽었습니다.** 앱은 멀쩡하고 알람만 안 울리니, 사용자는 과태료를 물고 나서야 알게 됩니다.
iOS는 같은 문제가 없어 로컬 알림이 그대로 잘 동작했습니다.

그래서 **안드로이드만 FCM 푸시로 전환**했습니다. FCM `notification` 페이로드는 앱이 아니라
Google Play 서비스가 직접 렌더링하므로 OEM 제한 목록을 우회합니다.

문제는 "예약 시각에" 푸시를 보내려면 서버가 필요한데, Firebase Cloud Functions·Cloud
Scheduler·Firestore TTL이 전부 **유료(Blaze) 플랜**을 요구한다는 점이었습니다. 대신
**Cloudflare Workers Cron Triggers**(무료, 카드 등록 불필요)로 1분마다 Firestore를 폴링해
발송 시각이 지난 알림을 FCM으로 보내는 구조를 택했습니다.

```
                 ┌──────────────── Android ────────────────┐
  [앱] 주차 시작 ─┤ PushService → Firestore                  │
                 │   users/{uid}/scheduledAlerts/{id}       │
                 │        ▲                                 │
                 │        │ 1분마다 cron 폴링                 │
                 │  [Cloudflare Worker] ──→ FCM ──→ [기기]   │
                 └──────────────────────────────────────────┘

                 ┌────────────────── iOS ───────────────────┐
  [앱] 주차 시작 ─┤ NotificationService → 로컬 알림 예약       │
                 └──────────────────────────────────────────┘
```

알림 문구·시점·색은 `lib/models/alert_schedule.dart` **한 곳**에만 두고 양쪽 경로가
공유하도록 해서, 발송 방식이 갈라져도 사용자가 받는 알림은 항상 같게 만들었습니다.

> **수정 시 주의** — 안드로이드 알림 관련 변경은 `lib/services/push_service.dart`(쓰기)와
> `worker/src/index.ts`(발송) **양쪽을 같이** 봐야 합니다. iOS는
> `lib/services/notification_service.dart` 하나면 됩니다.

<br>

---

### ⚒️ 개발 환경

#### **App**

- Flutter : 3.x (Dart SDK ^3.12.2)
- flutter_local_notifications : 19.4.2 / timezone : 0.10.1
- firebase_core · firebase_messaging · cloud_firestore · firebase_auth
- shared_preferences · permission_handler · vibration · google_fonts · intl

#### **Server**

- Cloudflare Workers (Cron Triggers, 무료 플랜)
- TypeScript : 5.6 / Wrangler : 4.x
- Firebase Firestore · Cloud Messaging(FCM) · 익명 인증

#### **Build**

- JDK 17 (`brew install openjdk@17`)
- Android SDK (`/opt/homebrew/share/android-commandlinetools`)

<br>

### 📁 프로젝트 구조

```
lib/
  main.dart                      앱 진입점 (다크 테마 고정)
  models/
    parking_state.dart           지속 상태 + 단계 경계 상수
    alert_schedule.dart          알림 시점·문구·색 — iOS/Android 공용 단일 출처
  services/
    schedule_service.dart        플랫폼 분기점 (Android→Push, iOS→Local)
    push_service.dart            Android: Firestore에 알림 문서 쓰기, FCM 토큰 관리
    notification_service.dart    iOS: 로컬 알림 예약 / 공용 채널·진동 정의
    storage_service.dart         SharedPreferences JSON 저장
  screens/home_screen.dart       메인 화면 (타이머 링, 기록, 설정)
  widgets/                       timer_ring · stats_row · history_list
  theme/app_theme.dart           색 팔레트 (알림 틴트의 원본)

worker/
  src/index.ts                   cron → Firestore 조회 → FCM 발송 → 만료 문서 정리
  src/privacy.ts                 개인정보처리방침 서빙 HTML

store/                           Play 스토어 출시 자료 (문구·자산·체크리스트)
firestore.rules                  본인 문서만 읽고 쓸 수 있도록 제한
```

<br>

### 🔏 수집하는 정보

인증은 **Firebase 익명 인증**만 사용합니다. 서버에 올라가는 것은 익명 UID, FCM 토큰,
예약된 알림(시각 + 문구)뿐이며 이름·이메일·위치는 일절 수집하지 않습니다. 알림 문서는
매일 KST 자정에 만료되고 워커가 직접 삭제합니다(Firestore TTL 정책은 유료 플랜 전용).

<br>

### 📦 출시 상태

Play 스토어 **미출시**. 빌드·서명·스토어 자산·문구는 모두 준비되었고 개발자
신원인증 대기 중입니다.
