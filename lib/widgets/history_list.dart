import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

class HistoryList extends StatelessWidget {
  const HistoryList({
    super.key,
    required this.history,
    required this.parkingLimit,
    this.maxItems = 20,
  });

  /// Most-recent-first list of "주차했어요" press timestamps.
  final List<DateTime> history;

  /// 현재 선택된 주차 제한 — 기록 간격이 이걸 넘으면 초과로 표시한다.
  /// 제한이 1/2/3시간으로 바뀔 수 있어서 전역 상수 대신 주입받는다.
  final Duration parkingLimit;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final items = history.take(maxItems).toList();
    final timeFmt = DateFormat('HH:mm');
    final dateFmt = DateFormat('M월 d일');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '주차 기록',
            style: AppTheme.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '아직 기록이 없어요.',
                style: AppTheme.inter(fontSize: 13, color: AppColors.textMuted),
              ),
            )
          else
            Column(
              children: List.generate(items.length, (i) {
                final entry = items[i];
                final previous =
                    i + 1 < history.length ? history[i + 1] : null;
                final gap = previous != null ? entry.difference(previous) : null;
                final isOvertime = gap != null && gap > parkingLimit;

                return Padding(
                  padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 10),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: isOvertime ? AppColors.overtime : AppColors.safe,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${dateFmt.format(entry)} ${timeFmt.format(entry)}',
                              style: AppTheme.jetBrainsMono(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (gap != null)
                              Text(
                                '이전 기록과 ${_formatGap(gap)} 간격',
                                style: AppTheme.inter(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isOvertime)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.overtime.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.overtime.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            '초과',
                            style: AppTheme.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.overtime,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  String _formatGap(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h시간 $m분';
    return '$m분';
  }
}
