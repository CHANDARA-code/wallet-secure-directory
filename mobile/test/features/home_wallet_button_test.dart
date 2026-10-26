import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_app/core/theme/app_theme.dart';
import 'package:wallet_app/features/auth/auth_notifier.dart';
import 'package:wallet_app/features/auth/auth_state.dart';
import 'package:wallet_app/features/documents/document_model.dart';
import 'package:wallet_app/features/documents/documents_notifier.dart';
import 'package:wallet_app/features/documents/home_screen.dart';
import 'package:wallet_app/features/wallet/wallet_provisioner.dart';

class DelayedWalletProvisioner implements WalletProvisioner {
  int callCount = 0;
  final Completer<WalletProvisionResult> completer =
      Completer<WalletProvisionResult>();

  @override
  Future<WalletProvisionResult> provision({
    required String documentId,
    required String token,
  }) async {
    callCount++;
    return completer.future;
  }
}

class FakeWalletProvisioner implements WalletProvisioner {
  int callCount = 0;
  final WalletProvisionResult resultToReturn;

  FakeWalletProvisioner(this.resultToReturn);

  @override
  Future<WalletProvisionResult> provision({
    required String documentId,
    required String token,
  }) async {
    callCount++;
    return resultToReturn;
  }
}

class _PresetAuthNotifier extends AuthNotifier {
  final AuthState _preset;
  _PresetAuthNotifier(this._preset);

  @override
  AuthState build() => _preset;
}

class _PresetDocumentsNotifier extends DocumentsNotifier {
  final DocumentsState _preset;
  _PresetDocumentsNotifier(this._preset);

  @override
  DocumentsState build() => _preset;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testDoc = const DocumentSummary(
    id: 'doc-123',
    type: 'driving_license',
    documentNumber: 'DL-99999999',
    status: 'issued',
  );

  Widget createHomeScreen({required WalletProvisioner provisioner}) {
    return ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(
          () => _PresetAuthNotifier(
            const Authenticated(token: 'valid-token', user: {}),
          ),
        ),
        documentsNotifierProvider.overrideWith(
          () => _PresetDocumentsNotifier(DocumentsLoaded([testDoc])),
        ),
        walletProvisionerProvider.overrideWithValue(provisioner),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    );
  }

  testWidgets(
    'two rapid taps trigger exactly one provision call and button re-enables afterwards',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provisioner = DelayedWalletProvisioner();
      await tester.pumpWidget(createHomeScreen(provisioner: provisioner));
      await tester.pumpAndSettle();

      final buttonFinder = find.widgetWithText(
        OutlinedButton,
        'Add to OS Wallet',
      );
      expect(buttonFinder, findsOneWidget);

      final initialButton = tester.widget<OutlinedButton>(buttonFinder);
      expect(initialButton.onPressed, isNotNull);

      await tester.tap(buttonFinder);
      await tester.tap(buttonFinder, warnIfMissed: false);
      await tester.pump();

      expect(provisioner.callCount, 1);

      final disabledButton = tester.widget<OutlinedButton>(buttonFinder);
      expect(disabledButton.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      provisioner.completer.complete(const WalletProvisionSuccess());
      await tester.pumpAndSettle();

      final reEnabledButton = tester.widget<OutlinedButton>(buttonFinder);
      expect(reEnabledButton.onPressed, isNotNull);
      expect(provisioner.callCount, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Pass added to wallet.'), findsOneWidget);
    },
  );

  testWidgets(
    'WalletProvisionCancelled does not show an error snackbar and re-enables button',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provisioner = FakeWalletProvisioner(
        const WalletProvisionCancelled(),
      );
      await tester.pumpWidget(createHomeScreen(provisioner: provisioner));
      await tester.pumpAndSettle();

      final buttonFinder = find.widgetWithText(
        OutlinedButton,
        'Add to OS Wallet',
      );
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(provisioner.callCount, 1);
      expect(find.byType(SnackBar), findsNothing);

      final reEnabledButton = tester.widget<OutlinedButton>(buttonFinder);
      expect(reEnabledButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'WalletProvisionBusy does not show an error snackbar and re-enables button',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provisioner = FakeWalletProvisioner(const WalletProvisionBusy());
      await tester.pumpWidget(createHomeScreen(provisioner: provisioner));
      await tester.pumpAndSettle();

      final buttonFinder = find.widgetWithText(
        OutlinedButton,
        'Add to OS Wallet',
      );
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(provisioner.callCount, 1);
      expect(find.byType(SnackBar), findsNothing);

      final reEnabledButton = tester.widget<OutlinedButton>(buttonFinder);
      expect(reEnabledButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'WalletProvisionFailure shows error snackbar and re-enables button',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final provisioner = FakeWalletProvisioner(
        const WalletProvisionFailure(
          'Pass provisioning timed out waiting for the wallet.',
        ),
      );
      await tester.pumpWidget(createHomeScreen(provisioner: provisioner));
      await tester.pumpAndSettle();

      final buttonFinder = find.widgetWithText(
        OutlinedButton,
        'Add to OS Wallet',
      );
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(provisioner.callCount, 1);
      expect(
        find.text('Pass provisioning timed out waiting for the wallet.'),
        findsOneWidget,
      );

      final reEnabledButton = tester.widget<OutlinedButton>(buttonFinder);
      expect(reEnabledButton.onPressed, isNotNull);
    },
  );
}
