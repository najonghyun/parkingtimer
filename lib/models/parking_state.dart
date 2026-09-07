import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// 1 "unit-minute" = 1 real minute, i.e. the full session is the real
/// 2-hour parking limit.
const Duration kUnitMinute = Duration(minutes: 1);

/// 홈 화면 세그먼트에서 고를 수 있는 주차 제한 (unit-minutes).
const List<int> kLimitOptions = [60, 120, 180];
const int kDefaultLimitMinutes = 120;

/// 단계 경계와 알림 시점은 전부 **마감까지 남은 unit-minutes**로 정의한다.
///
/// 제한이 1시간이든 3시간이든 "30분 전에 경고, 10분 전에 위험"이라는 체감은
/// 같아야 하기 때문 — 비율(전체의 75% 등)로 잡으면 3시간 주차에서 45분 전에
/// 경고가 와버려서 너무 이르다. 다급함은 남은 시간의 절대값이지 비율이 아니다.
///
/// 2시간 기준으로 환산하면 예전에 하드코딩돼 있던 70/90/110분과 정확히 같다.
const int kWarnBeforeEnd = 50; // 주의 진입
const int kDangerBeforeEnd = 30; // 위험 진입 (= 경고 알림)
const int kOvertimeBeforeEnd = 10; // 초과 진입 (= 위험 알림)

String todayKey([DateTime? now]) =>
    DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());

/// Persisted app state: current active timer + parking history for today.
class ParkingState {
  ParkingState({
    this.lastMoveTime,
    List<DateTime>? history,
    this.notifiedStage = 0,
    String? day,
    this.notificationsEnabled = true,
    this.onboardingShown = false,
    this.limitMinutes = kDefaultLimitMinutes,
  })  : history = history ?? [],
        day = day ?? todayKey();

  /// Start time of the current active timer. Null when idle.
  DateTime? lastMoveTime;

  /// Timestamps of every "주차했어요" press, most recent first. Capped at 100.
  List<DateTime> history;

  /// Highest stage index already reacted to in-app (haptics), to avoid
  /// re-triggering on every 1s UI tick. 0=none/safe, 1=warn, 2=danger,
  /// 3=overtime, 4=auto-stopped.
  int notifiedStage;

  /// yyyy-MM-dd of the last time this state was saved — used to detect a
  /// day rollover and reset counters.
  String day;

  bool notificationsEnabled;
  bool onboardingShown;

  /// 이번 주차의 제한 시간 (unit-minutes) — [kLimitOptions] 중 하나.
  int limitMinutes;

  /// 마감까지의 전체 길이. 링 게이지와 자동 정지 판정이 쓴다.
  Duration get parkingLimit => kUnitMinute * limitMinutes;

  /// 단계 경계를 "주차 시작 후 경과 unit-minutes"로 환산한 값.
  int get warnAtMinute => limitMinutes - kWarnBeforeEnd;
  int get dangerAtMinute => limitMinutes - kDangerBeforeEnd;
  int get overtimeAtMinute => limitMinutes - kOvertimeBeforeEnd;

  void addHistoryEntry(DateTime time) {
    history.insert(0, time);
    if (history.length > 100) {
      history = history.sublist(0, 100);
    }
  }

  int get todayCount {
    final key = todayKey();
    return history.where((t) => todayKey(t) == key).length;
  }

  DateTime? get lastParkedAt => history.isEmpty ? null : history.first;

  Duration elapsed({DateTime? now}) {
    if (lastMoveTime == null) return Duration.zero;
    return (now ?? DateTime.now()).difference(lastMoveTime!);
  }

  ParkingStage stageFor(Duration elapsed) {
    if (lastMoveTime == null) return ParkingStage.idle;
    final m = elapsed.inMicroseconds / kUnitMinute.inMicroseconds;
    if (m >= overtimeAtMinute) return ParkingStage.overtime;
    if (m >= dangerAtMinute) return ParkingStage.danger;
    if (m >= warnAtMinute) return ParkingStage.warn;
    return ParkingStage.safe;
  }

  Map<String, dynamic> toJson() => {
        'lastMoveTime': lastMoveTime?.toIso8601String(),
        'history': history.map((t) => t.toIso8601String()).toList(),
        'notifiedStage': notifiedStage,
        'day': day,
        'notificationsEnabled': notificationsEnabled,
        'onboardingShown': onboardingShown,
        'limitMinutes': limitMinutes,
      };

  factory ParkingState.fromJson(Map<String, dynamic> json) {
    return ParkingState(
      lastMoveTime: json['lastMoveTime'] != null
          ? DateTime.tryParse(json['lastMoveTime'] as String)
          : null,
      history: (json['history'] as List<dynamic>? ?? [])
          .map((e) => DateTime.tryParse(e as String))
          .whereType<DateTime>()
          .toList(),
      notifiedStage: json['notifiedStage'] as int? ?? 0,
      day: json['day'] as String? ?? todayKey(),
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      onboardingShown: json['onboardingShown'] as bool? ?? false,
      limitMinutes: json['limitMinutes'] as int? ?? kDefaultLimitMinutes,
    );
  }
}
