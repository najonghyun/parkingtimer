import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens ported 1:1 from the original web prototype.
class AppColors {
  AppColors._();

  static const background = Color(0xFF1B1E24);
  static const surface = Color(0xFF262A33);
  static const cardBorder = Color(0xFF333844);
  static const textPrimary = Color(0xFFF2F0EB);
  static const textMuted = Color(0xFF8B93A1);

  static const safe = Color(0xFF4CAF7D);
  static const warn = Color(0xFFE8A83C);
  static const danger = Color(0xFFE85C4A);
  static const overtime = Color(0xFFC23B2E);
  static const idle = Color(0xFF4A5060);
}

/// The five timer stages, in the order they occur.
enum ParkingStage { idle, safe, warn, danger, overtime }

extension ParkingStageX on ParkingStage {
  Color get color {
    switch (this) {
      case ParkingStage.idle:
        return AppColors.idle;
      case ParkingStage.safe:
        return AppColors.safe;
      case ParkingStage.warn:
        return AppColors.warn;
      case ParkingStage.danger:
        return AppColors.danger;
      case ParkingStage.overtime:
        return AppColors.overtime;
    }
  }

  String get label {
    switch (this) {
      case ParkingStage.idle:
        return '주차 대기';
      case ParkingStage.safe:
        return '안전';
      case ParkingStage.warn:
        return '주의';
      case ParkingStage.danger:
        return '위험';
      case ParkingStage.overtime:
        return '초과';
    }
  }
}

class AppTheme {
  AppTheme._();

  /// Headings / buttons.
  static TextStyle spaceGrotesk({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w700,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// Body / labels.
  static TextStyle inter({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// Timer digits — must always render as tabular (fixed-width) numerals.
  static TextStyle jetBrainsMono({
    double fontSize = 44,
    FontWeight fontWeight = FontWeight.w700,
    Color color = AppColors.textPrimary,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.background,
        primary: AppColors.safe,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
      ),
    );
  }
}
