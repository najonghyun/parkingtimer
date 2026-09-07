import 'dart:ui' show Color;

import '../theme/app_theme.dart';
import 'parking_state.dart';

/// The "kind" of alert, used to pick copy + vibration pattern.
enum AlertKind { warn, danger }

/// 위험 알림을 한 번 더 울리는 시점.
///
/// 매너모드에서는 소리를 쓸 수 없다 — 채널에 `USAGE_ALARM`을 지정해도 최신
/// 안드로이드가 발송 시점에 `USAGE_NOTIFICATION`으로 되돌려버린다(실기기
/// `dumpsys notification`의 effectiveNotificationChannel로 확인). 그래서
/// 진동이 유일한 신호인데, 진동 *패턴* 차이(짧게 2번 vs 길게 3번)는 주머니
/// 속에서 사실상 구분이 안 된다. 반면 "한 번 울리고 끝" vs "잠시 뒤 또 울림"은
/// 확실히 인지되므로, 위험 단계만 잠시 뒤 한 번 더 울린다.
///
/// 정확히 같은 시각에 두 번 보내면 안 된다 — 안드로이드는 진행 중인 진동을
/// 새 진동 요청으로 덮어쓰기 때문에, 두 번이 아니라 뭉개진 한 번으로 느껴진다.
/// 안드로이드 발송 주기(워커 크론)가 1분이라 최소 1 unit-minute만 띄워도
/// 다음 틱으로 갈린다.
const int kDangerRepeatBeforeEnd = 7;

/// 알림 아이콘 틴트 — 경고는 주황, 위험은 더 진한 빨강이라 알림창에서 한눈에
/// 구분된다. 안드로이드 푸시 경로에서도 쓰도록 Firestore 문서에 실려 나간다
/// (`PushService.scheduleAlerts` → 워커 → FCM `android.notification.color`).
Color alertAccentColor(AlertKind kind) =>
    kind == AlertKind.danger ? AppColors.overtime : AppColors.warn;

/// [alertAccentColor]를 FCM이 받는 `#rrggbb` 문자열로.
String alertAccentHex(AlertKind kind) {
  final argb = alertAccentColor(kind).toARGB32();
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// One alert in a parking session's notification batch.
class ScheduledAlert {
  const ScheduledAlert({
    required this.minute,
    required this.kind,
    required this.title,
    required this.body,
  });

  /// Elapsed unit-minutes since parking start (see [kUnitMinute]).
  final int minute;
  final AlertKind kind;
  final String title;
  final String body;
}

/// [limitMinutes] 제한짜리 주차 한 건의 알림 스케줄: 마감 30분 전(경고) 한 번,
/// 10분 전·7분 전(위험) 두 번. 마감 시점에는 알림 없이 타이머만 자동 리셋한다 —
/// "이미 초과했다"는 사후 알림은 할 수 있는 게 없어서 의미가 없기 때문.
///
/// 시점이 전부 마감 기준 고정 오프셋이라(자세한 배경은 [kWarnBeforeEnd] 참고)
/// 제목의 "N분 남았어요"는 제한 시간과 무관하게 항상 같고, 본문의 경과 시간만
/// 제한에 따라 달라진다.
///
/// 제목에 남은 시간을 숫자로 박아둔 건 의도적이다 — 매너모드에서 소리로
/// 긴박함을 전달할 수 없으니(자세한 배경은 [kDangerRepeatBeforeEnd] 참고),
/// 알림을 봤을 때 문구 자체가 남은 시간을 알려주게 했다.
///
/// Shared by both the iOS local-notification path
/// ([NotificationService.scheduleForParkingStart]) and the Android
/// Firestore-backed FCM path (`ScheduleService`/`PushService`), so the
/// timing + copy stay in exactly one place.
List<ScheduledAlert> buildAlertSchedule(int limitMinutes) {
  final limitLabel = formatDurationLabel(limitMinutes);
  return [
    ScheduledAlert(
      minute: limitMinutes - kDangerBeforeEnd,
      kind: AlertKind.warn,
      title: '⚠️ 경고 — $kDangerBeforeEnd분 남았어요',
      body: '주차 후 ${formatDurationLabel(limitMinutes - kDangerBeforeEnd)} '
          '경과했어요. 슬슬 재주차를 준비하세요.',
    ),
    ScheduledAlert(
      minute: limitMinutes - kOvertimeBeforeEnd,
      kind: AlertKind.danger,
      title: '🚨 위험! $kOvertimeBeforeEnd분 남았어요',
      body: '주차 후 ${formatDurationLabel(limitMinutes - kOvertimeBeforeEnd)} '
          '경과했어요. 지금 재주차하세요.',
    ),
    ScheduledAlert(
      minute: limitMinutes - kDangerRepeatBeforeEnd,
      kind: AlertKind.danger,
      title: '🚨 마지막 경고 — $kDangerRepeatBeforeEnd분 남았어요',
      body: '$limitLabel이 지나면 벌금 위험이 있어요. 지금 나가세요.',
    ),
  ];
}

/// `90` → `1시간 30분`, `120` → `2시간`, `50` → `50분`.
String formatDurationLabel(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '$mins분';
  if (mins == 0) return '$hours시간';
  return '$hours시간 $mins분';
}
