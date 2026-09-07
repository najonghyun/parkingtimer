import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatsRow extends StatelessWidget {
  const StatsRow({
    super.key,
    required this.todayCount,
    required this.lastParkedLabel,
  });

  final int todayCount;
  final String lastParkedLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(label: '오늘 주차 횟수', value: '$todayCount회'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(label: '마지막 주차 시각', value: lastParkedLabel),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.inter(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTheme.jetBrainsMono(fontSize: 20),
          ),
        ],
      ),
    );
  }
}
