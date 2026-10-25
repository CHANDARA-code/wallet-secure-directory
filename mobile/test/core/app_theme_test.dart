import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_app/core/theme/app_colors.dart';
import 'package:wallet_app/core/theme/app_theme.dart';

void main() {
  test('light theme uses the terracotta palette on a warm background', () {
    final theme = AppTheme.light;
    expect(theme.colorScheme.primary, AppColors.lightPrimary);
    expect(theme.scaffoldBackgroundColor, AppColors.lightBackground);
    expect(theme.colorScheme.surfaceContainer, AppColors.lightContainer);
    expect(theme.colorScheme.error, AppColors.lightError);
    expect(theme.brightness, Brightness.light);
  });

  test('dark theme uses the dark palette', () {
    final theme = AppTheme.dark;
    expect(theme.colorScheme.primary, AppColors.darkPrimary);
    expect(theme.scaffoldBackgroundColor, AppColors.darkBackground);
    expect(theme.colorScheme.onSurface, AppColors.darkText);
    expect(theme.brightness, Brightness.dark);
  });

  test('status colors extension is registered on both themes', () {
    expect(
      AppTheme.light.extension<StatusColors>()?.success,
      AppColors.lightSuccess,
    );
    expect(
      AppTheme.dark.extension<StatusColors>()?.warning,
      AppColors.darkWarning,
    );
  });

  test('buttons are 42dp tall with an 8dp radius', () {
    final style = AppTheme.light.filledButtonTheme.style!;
    expect(style.minimumSize!.resolve({})!.height, 42);
    final shape = style.shape!.resolve({}) as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('buttons keep a 48dp accessible tap target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: FilledButton(onPressed: () {}, child: const Text('Go')),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );
  });
}
