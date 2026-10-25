import 'package:flutter/material.dart';

abstract final class AppColors {
  static const lightBackground = Color(0xFFFAF9F5);
  static const lightContainer = Color(0xFFF4F3EE);
  static const lightElevated = Color(0xFFECEAE1);
  static const lightBorder = Color(0xFFE3E1D9);
  static const lightText = Color(0xFF1F1E1C);
  static const lightTextSecondary = Color(0xFF6B6862);
  static const lightTextTertiary = Color(0xFFB1ADA1);
  static const lightPrimary = Color(0xFFC15F3C);
  static const lightPrimaryHover = Color(0xFFA94F30);
  static const lightPrimaryActive = Color(0xFF8E3F24);
  static const lightSuccess = Color(0xFF4A7862);
  static const lightWarning = Color(0xFFB08838);
  static const lightError = Color(0xFFB3492F);

  static const darkBackground = Color(0xFF1A1917);
  static const darkContainer = Color(0xFF26241F);
  static const darkElevated = Color(0xFF322F29);
  static const darkBorder = Color(0xFF3D3A33);
  static const darkText = Color(0xFFF4F3EE);
  static const darkTextSecondary = Color(0xFFB1ADA1);
  static const darkTextTertiary = Color(0xFF7A766D);
  static const darkPrimary = Color(0xFFD97B57);
  static const darkPrimaryHover = Color(0xFFE68F6D);
  static const darkPrimaryActive = Color(0xFFC15F3C);
  static const darkSuccess = Color(0xFF6FA085);
  static const darkWarning = Color(0xFFD0A85C);
  static const darkError = Color(0xFFD9705A);
}

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.success, required this.warning});

  final Color success;
  final Color warning;

  static const light = StatusColors(
    success: AppColors.lightSuccess,
    warning: AppColors.lightWarning,
  );

  static const dark = StatusColors(
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
  );

  @override
  StatusColors copyWith({Color? success, Color? warning}) => StatusColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
  );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension StatusColorsContext on BuildContext {
  StatusColors get statusColors => Theme.of(this).extension<StatusColors>()!;
}
