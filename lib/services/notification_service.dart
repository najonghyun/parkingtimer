import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/alert_schedule.dart';
import '../models/parking_state.dart';

/// Local-notification plumbing shared by both platforms (channel setup,
/// permissions, immediate "show now" display) plus the full scheduling path
/// — which is used as the **only** delivery mechanism on iOS (reliable
/// without a server) and only for **foreground display** on Android, where
/// background delivery instead goes through FCM (see `PushService` /
/// `ScheduleService`) because OEM battery restrictions can silently kill
/// AlarmManager-scheduled alarms.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Fixed notification IDs, one per scheduled offset (order matches
  /// [buildAlertSchedule]) so re-scheduling always overwrites the same slots.
  static const int _baseId = 1000;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (e) {
      debugPrint('타임존 설정 실패, 기본값(UTC) 사용: $e');
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false, // we request explicitly below
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    await _plugin.initialize(initSettings);

    await _createAndroidChannels();
    _initialized = true;
  }

  /// Requests OS-level notification permission (Android 13+ POST_NOTIFICATIONS,
  /// iOS UNUserNotificationCenter alert/sound/badge).
  Future<bool> requestPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      // 정확한 알람 권한은 요청하지 않는다 — 안드로이드 배달은 FCM을 타고
      // 로컬 알람 스케줄링은 iOS 경로 전용이라, SCHEDULE_EXACT_ALARM 자체를
      // 매니페스트에서 뺐다 (AndroidManifest.xml 주석 참고).
      final granted = await androidImpl.requestNotificationsPermission();
      return granted ?? false;
    }

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      final granted = await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  /// Requests exemption from battery-optimization killing the app in the
  /// background (Android only; no-op elsewhere). Kept even though Android
  /// now relies on FCM for delivery, since it also helps the app stay alive
  /// long enough to register/refresh its FCM token.
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!defaultTargetPlatform.isAndroidPlatform) return;
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (!status.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> _createAndroidChannels() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return;

    for (final kind in AlertKind.values) {
      await androidImpl.createNotificationChannel(
        AndroidNotificationChannel(
          channelId(kind),
          _channelName(kind),
          description: _channelDescription(kind),
          importance: Importance.max,
          enableVibration: true,
          vibrationPattern: _vibrationPattern(kind),
          // `sound: null` + `playSound: true` uses the platform default
          // notification sound — no bundled audio asset required.
          //
          // 소리는 항상 켜두고, 실제로 울릴지 말지는 OS(매너모드)에 맡긴다.
          // 예전엔 앱 안에 소리 토글이 있었고 위험 단계는 `USAGE_ALARM`으로
          // 매너모드를 뚫으려 했지만, 안드로이드가 발송 시점에 그 요청을
          // 무시한다는 걸 실기기에서 확인해서(자세한 배경은 alert_schedule.dart
          // 의 [kDangerRepeatAtMinute] 주석) 토글째로 걷어냈다.
          playSound: true,
        ),
      );
      // 소리 토글 시절의 무음 채널이 기기에 남아 있으면 앱 알림 설정에 유령
      // 항목으로 보인다. 채널은 앱을 지우기 전까지 시스템에 남으므로 명시적으로
      // 정리해준다 (없는 채널이면 no-op).
      await androidImpl.deleteNotificationChannel('parking_${kind.name}_silent');
    }
  }

  /// Public so the FCM payload (sent from the Cloudflare Worker) can target
  /// the same pre-registered channel — Android only reads vibration/sound
  /// from the channel itself, not from the push payload.
  ///
  /// `_sound` 접미사는 소리 토글이 있던 시절의 잔재지만, 이미 기기에 만들어진
  /// 채널을 그대로 재사용하려고 유지한다 — ID를 바꾸면 기존 채널이 유령으로
  /// 남고 사용자가 조정해둔 알림 설정도 초기화된다.
  String channelId(AlertKind kind) => 'parking_${kind.name}_sound';

  String _channelName(AlertKind kind) {
    switch (kind) {
      case AlertKind.warn:
        return '주차 타이머 - 경고 알림';
      case AlertKind.danger:
        return '주차 타이머 - 위험 알림';
    }
  }

  String _channelDescription(AlertKind kind) {
    switch (kind) {
      case AlertKind.warn:
        return '주차 마감 30분 전 알림';
      case AlertKind.danger:
        return '주차 마감 10분 전 알림';
    }
  }

  Int64List _vibrationPattern(AlertKind kind) {
    switch (kind) {
      case AlertKind.warn:
        return Int64List.fromList([0, 250, 150, 250]);
      case AlertKind.danger:
        return Int64List.fromList([0, 400, 150, 400, 150, 400]);
    }
  }

  /// Shows a notification immediately — used on Android to render an
  /// incoming FCM message while the app is in the foreground (FCM
  /// "notification" payloads don't auto-display then).
  Future<void> showNow({
    required AlertKind kind,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId(kind),
          _channelName(kind),
          channelDescription: _channelDescription(kind),
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
          vibrationPattern: _vibrationPattern(kind),
          playSound: true,
          category: AndroidNotificationCategory.alarm,
          color: alertAccentColor(kind),
          // 위험 알림은 눌러도 알림창에 남는다 — 나중에 폰을 봤을 때 "아직
          // 처리 안 한 위험 알림"이 보이게. 경고는 기본대로 눌러서 사라짐.
          autoCancel: kind != AlertKind.danger,
        ),
      ),
    );
  }

  /// iOS-only delivery path: cancels any previously-scheduled alerts and
  /// schedules a fresh local-notification batch for a parking session that
  /// started at [startTime]. (Android delivery goes through FCM instead —
  /// see `ScheduleService`.)
  Future<void> scheduleForParkingStart(
    DateTime startTime, {
    required bool notificationsEnabled,
    required int limitMinutes,
  }) async {
    await cancelAll();
    if (!notificationsEnabled) return;

    final scheduleMode = await _resolveAndroidScheduleMode();

    final schedule = buildAlertSchedule(limitMinutes);
    for (var i = 0; i < schedule.length; i++) {
      final alert = schedule[i];
      final fireAt = startTime.add(kUnitMinute * alert.minute);
      if (fireAt.isBefore(DateTime.now())) continue;

      final tzTime = tz.TZDateTime.from(fireAt, tz.local);

      try {
        await _plugin.zonedSchedule(
          _baseId + i,
          alert.title,
          alert.body,
          tzTime,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId(alert.kind),
              _channelName(alert.kind),
              channelDescription: _channelDescription(alert.kind),
              importance: Importance.max,
              priority: Priority.high,
              enableVibration: true,
              vibrationPattern: _vibrationPattern(alert.kind),
              playSound: true,
              category: AndroidNotificationCategory.alarm,
              color: alertAccentColor(alert.kind),
              autoCancel: alert.kind != AlertKind.danger,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
              sound: 'default',
              interruptionLevel: InterruptionLevel.timeSensitive,
            ),
          ),
          androidScheduleMode: scheduleMode,
        );
      } catch (e) {
        // Don't let one failed slot (e.g. OEM alarm-count limits) cancel
        // every alert scheduled after it.
        debugPrint('알림 예약 실패 (${alert.minute}분, ${alert.kind}): $e');
      }
    }
  }

  Future<AndroidScheduleMode> _resolveAndroidScheduleMode() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) {
      // iOS: androidScheduleMode is ignored, any value is fine.
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    try {
      final canScheduleExact =
          await androidImpl.canScheduleExactNotifications();
      return (canScheduleExact ?? false)
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (e) {
      debugPrint('정확한 알람 권한 확인 실패, inexact로 대체: $e');
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}

extension on TargetPlatform {
  bool get isAndroidPlatform => this == TargetPlatform.android;
}
