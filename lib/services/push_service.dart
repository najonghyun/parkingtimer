import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/alert_schedule.dart';
import '../models/parking_state.dart';
import 'notification_service.dart';

/// Android-only push path: schedules the 10-alert batch as Firestore
/// documents (instead of local `AlarmManager` alarms) so a Cloudflare Worker
/// can deliver them via FCM. FCM "notification" payloads are rendered by
/// Google Play Services directly, which survives OEM background-restriction
/// lists (e.g. Samsung "제한된 앱") that silently kill local alarms.
///
/// iOS never touches this class — its local notifications are already
/// reliable, so [NotificationService.scheduleForParkingStart] is used as-is.
class PushService {
  PushService(this._localDisplay);

  final NotificationService _localDisplay;

  bool _initialized = false;
  String? _uid;

  Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final credential = await FirebaseAuth.instance.signInAnonymously();
    _uid = credential.user?.uid;

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _saveToken(token);
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);

    FirebaseMessaging.onMessage.listen(_showForegroundMessage);

    _initialized = true;
  }

  Future<void> _saveToken(String token) async {
    final uid = _uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'fcmToken': token, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// FCM "notification" messages don't auto-display while the app is in the
  /// foreground, so render them ourselves via the same local channel setup
  /// used on iOS (keeps look/vibration consistent).
  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final kind = AlertKind.values.firstWhere(
      (k) => k.name == message.data['kind'],
      orElse: () => AlertKind.warn,
    );
    final title = message.notification?.title ?? message.data['title'] ?? '';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    await _localDisplay.showNow(kind: kind, title: title, body: body);
  }

  /// Deletes any still-pending (unsent) alerts, then writes a fresh 10-alert
  /// batch for a parking session that started at [startTime].
  Future<void> scheduleAlerts(
    DateTime startTime, {
    required bool notificationsEnabled,
    required int limitMinutes,
  }) async {
    await cancelPendingAlerts();
    final uid = _uid;
    if (!notificationsEnabled || uid == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      debugPrint('FCM 토큰 없음 — 알림 예약 건너뜀');
      return;
    }

    final schedule = buildAlertSchedule(limitMinutes);
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('scheduledAlerts');
    final batch = FirebaseFirestore.instance.batch();
    final now = DateTime.now();

    for (final alert in schedule) {
      final fireAt = startTime.add(kUnitMinute * alert.minute);
      if (fireAt.isBefore(now)) continue;
      batch.set(col.doc(), {
        'fireAt': Timestamp.fromDate(fireAt),
        'title': alert.title,
        'body': alert.body,
        'kind': alert.kind.name,
        'channelId': _localDisplay.channelId(alert.kind),
        // 아이콘 틴트는 앱 팔레트(app_theme.dart)가 원본이라 여기서 계산해
        // 실어 보낸다 — 워커는 그대로 FCM에 넘기기만 함.
        'color': alertAccentHex(alert.kind),
        'fcmToken': token,
        'sent': false,
        'createdAt': FieldValue.serverTimestamp(),
        // Firestore TTL policy (see firestore.indexes.json setup) deletes
        // the document once this passes — next midnight KST, same cadence
        // as the on-device daily history reset.
        'expireAt': Timestamp.fromDate(_nextKstMidnightUtc(now)),
      });
    }
    await batch.commit();
  }

  Future<void> cancelPendingAlerts() async {
    final uid = _uid;
    if (uid == null) return;
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('scheduledAlerts');
    final pending = await col.where('sent', isEqualTo: false).get();
    if (pending.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in pending.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}

/// UTC instant of the next midnight in KST (UTC+9, no DST) strictly after
/// [instant] — used as the Firestore TTL expiry so alert docs get cleaned
/// up on the same daily cadence as the on-device history reset, regardless
/// of the device's own timezone setting.
DateTime _nextKstMidnightUtc(DateTime instant) {
  final kstNow = instant.toUtc().add(const Duration(hours: 9));
  final kstMidnightTomorrow = DateTime.utc(kstNow.year, kstNow.month, kstNow.day + 1);
  return kstMidnightTomorrow.subtract(const Duration(hours: 9));
}
