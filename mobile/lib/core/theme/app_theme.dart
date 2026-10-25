import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static const double _controlHeight = 42;
  static const double _buttonRadius = 8;
  static const double _cardRadius = 12;
  static const double _fieldRadius = 10;
  static const double _chipRadius = 6;

  static ThemeData get light => _build(
    brightness: Brightness.light,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.lightPrimary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.lightElevated,
      onPrimaryContainer: AppColors.lightText,
      secondary: AppColors.lightTextSecondary,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.lightElevated,
      onSecondaryContainer: AppColors.lightText,
      error: AppColors.lightError,
      onError: Colors.white,
      surface: AppColors.lightBackground,
      onSurface: AppColors.lightText,
      onSurfaceVariant: AppColors.lightTextSecondary,
      outline: AppColors.lightBorder,
      outlineVariant: AppColors.lightBorder,
      surfaceContainerLowest: AppColors.lightBackground,
      surfaceContainerLow: AppColors.lightContainer,
      surfaceContainer: AppColors.lightContainer,
      surfaceContainerHigh: AppColors.lightElevated,
      surfaceContainerHighest: AppColors.lightElevated,
    ),
    primaryActive: AppColors.lightPrimaryActive,
    hint: AppColors.lightTextTertiary,
    status: StatusColors.light,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkBackground,
      primaryContainer: AppColors.darkElevated,
      onPrimaryContainer: AppColors.darkText,
      secondary: AppColors.darkTextSecondary,
      onSecondary: AppColors.darkBackground,
      secondaryContainer: AppColors.darkElevated,
      onSecondaryContainer: AppColors.darkText,
      error: AppColors.darkError,
      onError: AppColors.darkBackground,
      surface: AppColors.darkBackground,
      onSurface: AppColors.darkText,
      onSurfaceVariant: AppColors.darkTextSecondary,
      outline: AppColors.darkBorder,
      outlineVariant: AppColors.darkBorder,
      surfaceContainerLowest: AppColors.darkBackground,
      surfaceContainerLow: AppColors.darkContainer,
      surfaceContainer: AppColors.darkContainer,
      surfaceContainerHigh: AppColors.darkElevated,
      surfaceContainerHighest: AppColors.darkElevated,
    ),
    primaryActive: AppColors.darkPrimaryActive,
    hint: AppColors.darkTextTertiary,
    status: StatusColors.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required Color primaryActive,
    required Color hint,
    required StatusColors status,
  }) {
    final borderSide = BorderSide(color: colorScheme.outline);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_buttonRadius),
    );
    final buttonSize = const Size.fromHeight(_controlHeight);
    final buttonText = const TextStyle(fontWeight: FontWeight.w600);

    OutlineInputBorder fieldBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(_fieldRadius),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      dividerColor: colorScheme.outline,
      extensions: [status],
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 72,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
          side: borderSide,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: buttonSize,
              shape: buttonShape,
              textStyle: buttonText,
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return colorScheme.onSurface.withValues(alpha: 0.12);
                }
                if (states.contains(WidgetState.pressed)) return primaryActive;
                return colorScheme.primary;
              }),
            ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
          foregroundColor: colorScheme.onSurface,
          side: borderSide,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: buttonText,
          foregroundColor: colorScheme.primary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        hintStyle: TextStyle(color: hint),
        border: fieldBorder(colorScheme.outline),
        enabledBorder: fieldBorder(colorScheme.outline),
        focusedBorder: fieldBorder(colorScheme.primary, 1.5),
        errorBorder: fieldBorder(colorScheme.error),
        focusedErrorBorder: fieldBorder(colorScheme.error, 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        side: borderSide,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_chipRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
          side: borderSide,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        contentTextStyle: TextStyle(color: colorScheme.onSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
          side: borderSide,
        ),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outline, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
    );
  }
}
