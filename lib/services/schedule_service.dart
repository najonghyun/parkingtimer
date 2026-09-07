import 'dart:io';

import 'notification_service.dart';
import 'push_service.dart';

/// Single entry point `HomeScreen` calls to (re)schedule or cancel the
/// 10-alert batch — routes to the right underlying mechanism per platform:
/// FCM/Firestore on Android (survives OEM background restrictions), plain
/// local notifications on iOS (already reliable there).
class ScheduleService {
  ScheduleService({
    required NotificationService notificationService,
    required PushService pushService,
  })  : _notificationService = notificationService,
        _pushService = pushService;

  final NotificationService _notificationService;
  final PushService _pushService;

  Future<void> scheduleForParkingStart(
    DateTime startTime, {
    required bool notificationsEnabled,
    required int limitMinutes,
  }) {
    if (Platform.isAndroid) {
      return _pushService.scheduleAlerts(
        startTime,
        notificationsEnabled: notificationsEnabled,
        limitMinutes: limitMinutes,
      );
    }
    return _notificationService.scheduleForParkingStart(
      startTime,
      notificationsEnabled: notificationsEnabled,
      limitMinutes: limitMinutes,
    );
  }

  Future<void> cancelAll() {
    if (Platform.isAndroid) {
      return _pushService.cancelPendingAlerts();
    }
    return _notificationService.cancelAll();
  }
}
