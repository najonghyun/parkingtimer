import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import '../models/alert_schedule.dart';
import '../models/parking_state.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/schedule_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/history_list.dart';
import '../widgets/stats_row.dart';
import '../widgets/timer_ring.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _storage = StorageService();
  final _notifications = NotificationService();
  late final _pushService = PushService(_notifications);
  late final _schedule = ScheduleService(
    notificationService: _notifications,
    pushService: _pushService,
  );

  ParkingState _state = ParkingState();
  Timer? _ticker;
  bool _loading = true;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    _lifecycleState = lifecycleState;
    if (lifecycleState == AppLifecycleState.resumed) {
      _handleDayRolloverAndReload();
    }
  }

  Future<void> _bootstrap() async {
    try {
      // A misbehaving OS/plugin call must never hard-freeze the UI on the
      // loading spinner — fall back gracefully if it takes too long.
      await _notifications.initialize().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('알림 서비스 초기화 실패(계속 진행): $e');
    }
    try {
      // Android-only; no-ops immediately on iOS. Needs its own network
      // round trip (Firebase init + anonymous sign-in), so give it more
      // room than the local plugin before giving up.
      await _pushService.initialize().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('푸시 서비스 초기화 실패(계속 진행): $e');
    }
    final state = await _storage.load();
    _applyDayRollover(state);
    if (!mounted) return;
    setState(() {
      _state = state;
      _loading = false;
    });
    _startTicker();

    // First-launch onboarding: permissions + battery optimization guidance.
    if (!state.onboardingShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOnboarding());
    }
  }

  Future<void> _handleDayRolloverAndReload() async {
    final state = await _storage.load();
    final changed = _applyDayRollover(state);
    if (changed) await _storage.save(state);
    setState(() => _state = state);
  }

  /// Resets today's counters if the stored `day` differs from today.
  /// Returns true if a reset happened.
  bool _applyDayRollover(ParkingState state) {
    final today = todayKey();
    if (state.day != today) {
      state.day = today;
      state.lastMoveTime = null;
      state.history = [];
      state.notifiedStage = 0;
      return true;
    }
    return false;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  Future<void> _onTick() async {
    if (!mounted) return;
    if (_state.lastMoveTime == null) {
      setState(() {});
      return;
    }

    final elapsed = _state.elapsed();
    if (elapsed >= _state.parkingLimit) {
      await _autoStop();
      return;
    }

    final stageIndex = _stageIndex(_state.stageFor(elapsed));
    if (stageIndex > _state.notifiedStage) {
      _state.notifiedStage = stageIndex;
      await _storage.save(_state);
      // Only buzz in-app if the user is actually looking at the screen —
      // the OS-scheduled notification already handles the background case,
      // and firing this too made it look like a phantom "silent" alert.
      if (_lifecycleState == AppLifecycleState.resumed) {
        unawaited(_foregroundVibrate(stageIndex));
      }
    }

    setState(() {});
  }

  int _stageIndex(ParkingStage stage) {
    switch (stage) {
      case ParkingStage.idle:
      case ParkingStage.safe:
        return 0;
      case ParkingStage.warn:
        return 1;
      case ParkingStage.danger:
        return 2;
      case ParkingStage.overtime:
        return 3;
    }
  }

  Future<void> _foregroundVibrate(int stageIndex) async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) return;
    switch (stageIndex) {
      case 1:
        Vibration.vibrate(pattern: const [0, 250, 150, 250]);
        break;
      case 2:
        Vibration.vibrate(pattern: const [0, 400, 150, 400, 150, 400]);
        break;
      case 3:
        Vibration.vibrate(
          pattern: const [0, 600, 120, 600, 120, 600, 120, 600],
        );
        break;
    }
  }

  Future<void> _autoStop() async {
    _state.lastMoveTime = null;
    _state.notifiedStage = 4;
    await _storage.save(_state);
    await _schedule.cancelAll();
    if (_lifecycleState == AppLifecycleState.resumed) {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(
          pattern: const [0, 600, 120, 600, 120, 600, 120, 600, 120, 600],
        );
      } else {
        HapticFeedback.heavyImpact();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _onParkNow() async {
    final now = DateTime.now();
    // Apply any pending day rollover first so today's counters start clean.
    _applyDayRollover(_state);
    _state.lastMoveTime = now;
    _state.addHistoryEntry(now);
    _state.notifiedStage = 0;
    await _storage.save(_state);

    HapticFeedback.mediumImpact();

    await _schedule.scheduleForParkingStart(
      now,
      notificationsEnabled: _state.notificationsEnabled,
      limitMinutes: _state.limitMinutes,
    );

    setState(() {});
  }

  Future<void> _toggleNotifications() async {
    _state.notificationsEnabled = !_state.notificationsEnabled;
    await _storage.save(_state);
    if (_state.lastMoveTime != null) {
      await _schedule.scheduleForParkingStart(
        _state.lastMoveTime!,
        notificationsEnabled: _state.notificationsEnabled,
        limitMinutes: _state.limitMinutes,
      );
    }
    setState(() {});
  }

  /// 주차 제한을 바꾸면 단계 경계가 통째로 움직인다. 진행 중인 타이머에
  /// 그걸 그대로 적용하면 링 색과 남은 시간이 한꺼번에 튀어서 무슨 일이
  /// 벌어진 건지 알기 어렵기 때문에, 주차 중일 때는 "초기화하고 새로
  /// 시작"이라고 명시적으로 확인받는다. 대기 중이면 그냥 바로 바뀐다.
  Future<void> _onLimitChanged(int limitMinutes) async {
    if (limitMinutes == _state.limitMinutes) return;

    if (_state.lastMoveTime != null) {
      final confirmed = await _confirmLimitChange(limitMinutes);
      if (confirmed != true) return;
      await _schedule.cancelAll();
      _state.lastMoveTime = null;
      _state.notifiedStage = 0;
    }

    _state.limitMinutes = limitMinutes;
    await _storage.save(_state);
    HapticFeedback.selectionClick();
    if (mounted) setState(() {});
  }

  Future<bool?> _confirmLimitChange(int limitMinutes) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '타이머가 초기화돼요',
          style: AppTheme.spaceGrotesk(fontSize: 18),
        ),
        content: Text(
          '주차 제한을 ${formatDurationLabel(limitMinutes)}으로 바꾸면 진행 중인 '
          '타이머가 초기화되고 예약된 알림도 취소돼요. 주차 기록은 그대로 남아요.',
          style: AppTheme.inter(fontSize: 14, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '취소',
              style: AppTheme.inter(
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '초기화하고 변경',
              style: AppTheme.inter(
                fontWeight: FontWeight.w700,
                color: AppColors.overtime,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOnboarding() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          '알림 권한이 필요해요',
          style: AppTheme.spaceGrotesk(fontSize: 18),
        ),
        content: Text(
          '주차 타이머는 2시간 규정을 지킬 수 있도록 단계별로 알림을 보내드려요.\n\n'
          '• 알림 권한을 허용해주세요.\n'
          '• Android 기기에서는 배터리 최적화 예외를 설정해야 앱이 백그라운드에서 '
          '꺼지지 않고 알림이 정시에 울려요. (삼성/샤오미 등 일부 제조사는 '
          '자체 절전 기능으로 알림을 막을 수 있으니, 설정에서 이 앱을 '
          '"제한 없음"으로 지정해주세요.)',
          style: AppTheme.inter(fontSize: 14, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _notifications.requestPermission();
              await _notifications.requestIgnoreBatteryOptimizations();
              _state.onboardingShown = true;
              await _storage.save(_state);
            },
            child: Text(
              '권한 설정하기',
              style: AppTheme.inter(
                fontWeight: FontWeight.w600,
                color: AppColors.safe,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRemaining(Duration remaining) {
    final total = remaining.isNegative ? Duration.zero : remaining;
    final h = total.inHours;
    final m = total.inMinutes % 60;
    final s = total.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.safe)),
      );
    }

    final elapsed = _state.elapsed();
    final remaining = _state.parkingLimit - elapsed;
    final stage = _state.stageFor(elapsed);
    final progress = _state.lastMoveTime == null
        ? 1.0
        : (remaining.inMilliseconds / _state.parkingLimit.inMilliseconds);
    final timeLabel = _state.lastMoveTime == null
        ? _formatRemaining(_state.parkingLimit)
        : _formatRemaining(remaining);

    final lastParkedLabel = _state.lastParkedAt == null
        ? '-'
        : _timeOnly(_state.lastParkedAt!);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(limitMinutes: _state.limitMinutes),
              const SizedBox(height: 20),
              Center(
                child: TimerRing(
                  progress: progress,
                  stage: stage,
                  timeLabel: timeLabel,
                ),
              ),
              const SizedBox(height: 28),
              _ParkButton(onPressed: _onParkNow),
              const SizedBox(height: 14),
              // 소리 토글은 없앴다 — 매너모드를 뚫을 방법이 없어서(자세한
              // 배경은 alert_schedule.dart의 [kDangerRepeatAtMinute] 주석)
              // 소리 여부는 OS 설정에 맡기는 게 맞다고 판단.
              _ToggleChip(
                label: '알림',
                enabled: _state.notificationsEnabled,
                onIcon: Icons.notifications_active_outlined,
                offIcon: Icons.notifications_off_outlined,
                onPressed: _toggleNotifications,
              ),
              const SizedBox(height: 24),
              StatsRow(
                todayCount: _state.todayCount,
                lastParkedLabel: lastParkedLabel,
              ),
              const SizedBox(height: 16),
              HistoryList(
                history: _state.history,
                parkingLimit: _state.parkingLimit,
              ),
              const SizedBox(height: 16),
              _LimitSelector(
                selected: _state.limitMinutes,
                onChanged: _onLimitChanged,
              ),
              const SizedBox(height: 20),
              _FooterNote(limitMinutes: _state.limitMinutes),
              const SizedBox(height: 16),
              _ResetAllButton(onPressed: _confirmAndResetAll),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndResetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '초기화하시겠습니까?',
          style: AppTheme.spaceGrotesk(fontSize: 18),
        ),
        content: Text(
          '오늘의 주차 기록과 통계가 모두 삭제돼요. 진행 중인 타이머가 있다면 '
          '함께 중지되고 예약된 알림도 취소돼요. 되돌릴 수 없어요.',
          style: AppTheme.inter(fontSize: 14, color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '취소',
              style: AppTheme.inter(
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '초기화',
              style: AppTheme.inter(
                fontWeight: FontWeight.w700,
                color: AppColors.overtime,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _schedule.cancelAll();
    _state.lastMoveTime = null;
    _state.history = [];
    _state.notifiedStage = 0;
    await _storage.save(_state);
    if (mounted) setState(() {});
  }

  String _timeOnly(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.limitMinutes});

  /// 부제에 현재 선택된 제한을 그대로 보여준다 — 예전엔 '2시간 주차 규정'이
  /// 하드코딩돼 있었는데, 제한을 1/3시간으로 바꿀 수 있게 된 뒤로는 틀린
  /// 정보가 됐다.
  final int limitMinutes;

  @override
  Widget build(BuildContext context) {
    final isTestMode = kUnitMinute != const Duration(minutes: 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${formatDurationLabel(limitMinutes)} 주차 규정',
              style: AppTheme.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            if (isTestMode) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warn.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.warn.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  '⚡ 테스트 모드 (1분=${kUnitMinute.inSeconds}초)',
                  style: AppTheme.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warn,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '차빼요',
          style: AppTheme.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ParkButton extends StatelessWidget {
  const _ParkButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.safe,
          foregroundColor: const Color(0xFF10231A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(
          '🅿️ 지금 주차했어요',
          style: AppTheme.spaceGrotesk(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF10231A),
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.enabled,
    required this.onIcon,
    required this.offIcon,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final IconData onIcon;
  final IconData offIcon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? AppColors.safe.withValues(alpha: 0.5) : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              enabled ? onIcon : offIcon,
              size: 18,
              color: enabled ? AppColors.safe : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              '$label ${enabled ? '켜짐' : '꺼짐'}',
              style: AppTheme.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: enabled ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 주차 제한 시간(1/2/3시간) 세그먼트. 설정 화면이 아니라 홈에 있는 이유는
/// 이 값이 "한 번 정하고 마는 설정"이 아니라 주차 장소마다 바뀌는 값이기
/// 때문 — 마트는 2시간, 카페는 1시간처럼 매번 다르다.
class _LimitSelector extends StatelessWidget {
  const _LimitSelector({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '주차 제한 기준 시간',
          style: AppTheme.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              for (final minutes in kLimitOptions)
                Expanded(
                  child: _LimitOption(
                    label: formatDurationLabel(minutes),
                    isSelected: minutes == selected,
                    onTap: () => onChanged(minutes),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LimitOption extends StatelessWidget {
  const _LimitOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.safe.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.safe.withValues(alpha: 0.6) : Colors.transparent,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTheme.inter(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote({required this.limitMinutes});

  final int limitMinutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      // 알림 시점은 마감 기준 고정 오프셋이라 제한이 바뀌어도 이 문장은
      // 그대로 맞다 — 마감 시각만 선택값을 따라간다.
      child: Text(
        '알림 정책: 마감 $kDangerBeforeEnd분 전에 경고 알림, '
        '$kOvertimeBeforeEnd분 전과 $kDangerRepeatBeforeEnd분 전에 위험 알림이 '
        '울려요. ${formatDurationLabel(limitMinutes)}이 지나면 알림 없이 타이머가 '
        '자동으로 멈추고 대기 상태로 돌아가니, "지금 주차했어요"를 다시 눌러 '
        '새 타이머를 시작해주세요.',
        style: AppTheme.inter(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w400),
      ),
    );
  }
}

class _ResetAllButton extends StatelessWidget {
  const _ResetAllButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          '전체 기록 초기화',
          style: AppTheme.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
