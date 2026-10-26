# Native Wallet Provisioning Architecture & Verification

## 1. Overview & Architecture

The mobile wallet feature connects Flutter identity documents to native mobile wallets (Apple Wallet on iOS via PassKit and Google Wallet on Android via Google Play Services).

### Bridge Hierarchy & Abstractions
- **`NativeWalletBridge`**: The core interface in `lib/features/wallet/wallet_provisioner.dart` defining:
  - `bool get isAvailable`
  - `Future<WalletProvisionResult> addApplePass(Uint8List passBytes)`
  - `Future<WalletProvisionResult> addGooglePass(String jwt)`
- **`PlatformNativeWalletBridge`**: The production implementation. It directs calls to the iOS `MethodChannel` (`com.example.wallet_app/wallet`) on iOS devices and to the `add_to_google_wallet` plugin (`com.droidsonroids/loyalty_pass`) on Android devices.
- **`UnavailableNativeWalletBridge`**: Fallback bridge used for unsupported platforms (web, desktop) or when native provisioning is disabled.
- **`nativeWalletBridgeProvider`**: Riverpod provider returning `PlatformNativeWalletBridge` on iOS and Android, and `UnavailableNativeWalletBridge` elsewhere.
- **`GoogleWalletProvisioner` & `AppleWalletProvisioner`**: High-level provisioners coordinating backend pass retrieval (`ApiClient`), stub verification, availability checks, and native delegation.

---

## 2. Platform Channel Contracts

### iOS MethodChannel Contract

- **Channel Name**: `com.example.wallet_app/wallet`
- **Method**: `addPass`
- **Arguments**: `Uint8List` (raw binary data of the `.pkpass` bundle, transferred as `FlutterStandardTypedData` / `Data`).
- **Return Values**:
  - `true` (or `"confirmed"`): Pass was confirmed in the system wallet library via `PKPassLibrary().containsPass(pass)`.
  - `false` (or `"cancelled"`): The `PKAddPassesViewController` was dismissed without adding the pass (user pressed Cancel).
  - `"unknown"` / `null`: Confirmation state could not be determined. Mapped by Dart directly to `WalletProvisionFailure('Pass addition could not be confirmed.')`, never to `WalletProvisionSuccess`.
- **Native Error Codes**:
  - `busy`: Thrown when a pass addition request is already in progress (`pendingResult != nil`). Mapped in Dart to `WalletProvisionBusy` (a quiet outcome without error snackbars).
  - `invalid_pass`: Thrown if `PKPass(data:)` throws, indicating corrupted archive, invalid `pass.json`, or missing/invalid cryptographic signature.
  - `unavailable`: Thrown when `!PKAddPassesViewController.canAddPasses()`, e.g. on iPad or MDM-restricted devices, or if no key window view controller is found.
  - `invalid_args`: Arguments are not valid byte buffers.

### Swift `WalletChannelHandler.swift` Re-entrancy & Exactly-Once Invocations

A critical defect previously existed where concurrent calls to `addPass` overwrote `self.pendingResult`, permanently dropping the first callback and hanging the first Dart Future. To resolve this:

1. **Re-entrancy Guard**:
   At the start of `addPass`, `WalletChannelHandler` checks:
   ```swift
   guard self.pendingResult == nil else {
     result(FlutterError(code: "busy", message: "Pass addition already in progress", details: nil))
     return
   }
   ```
   If a pass addition is currently active, `result` is invoked immediately with code `"busy"` without mutating `self.pendingResult` or `self.pendingPass`.

2. **Exactly-Once Guarantee on Every Path**:
   Every code path in `WalletChannelHandler` invokes the Flutter `result` callback exactly once:
   - Unknown method: `result(FlutterMethodNotImplemented)`.
   - Re-entrancy conflict: `result(FlutterError(code: "busy", ...))`.
   - Device cannot add passes: `result(FlutterError(code: "unavailable", ...))`.
   - Missing/invalid pass byte argument: `result(FlutterError(code: "invalid_args", ...))`.
   - Corrupt pass bundle / signature exception: `result(FlutterError(code: "invalid_pass", ...))`.
   - Pass already exists in library: `result(true)`.
   - Failed view controller initialization: `result(FlutterError(code: "invalid_pass", ...))`.
   - Missing active foreground view controller: `result(FlutterError(code: "unavailable", ...))`.
   - Modal dismissal (`addPassesViewControllerDidFinish`):
     ```swift
     let pass = self.pendingPass
     let res = self.pendingResult
     self.pendingPass = nil
     self.pendingResult = nil

     controller.dismiss(animated: true) {
       guard let res = res else { return }
       guard let pass = pass else {
         res(false)
         return
       }
       let library = PKPassLibrary()
       let added = library.containsPass(pass)
       res(added)
     }
     ```
     `self.pendingResult` and `self.pendingPass` are cleared synchronously upon entry to `addPassesViewControllerDidFinish`. The captured `res` closure is invoked once upon dismissal completion. Repeated or late delegate calls see `res == nil` and safely no-op.

> **Verification Notice**: Because Swift double-invocation and iOS out-of-process sheet presentation cannot be exercised by Dart headless unit tests, the Swift handler's re-entrancy guard and exactly-once invocation guarantees are verified strictly through line-by-line static review and native compilation, not by a Dart runtime test.

---

### Android Google Wallet Plugin Contract

- **Plugin**: `add_to_google_wallet` (`com.droidsonroids/loyalty_pass`)
- **Availability Pre-Check**: `AddToGoogleWallet().isGoogleWalletApiAvailable` is queried first. If `false`, returns `WalletProvisionUnavailable('Google Wallet is not available on this device')`.
- **Method**: `saveLoyaltyPass` taking JWT string.
- **Callbacks**:
  - `onSuccess`: User completed Google Wallet addition flow -> `WalletProvisionSuccess()`.
  - `onCanceled`: User dismissed the sheet -> `WalletProvisionCancelled()`.
  - `onError`: Google Pay Services returned an error code or message -> `WalletProvisionFailure('Google Wallet error: $error')`.
  - `PlatformException`: Handled defensively -> `busy` code yields `WalletProvisionBusy()`; generic exceptions yield `WalletProvisionFailure`.

---

### Bridge Timeout & Late Callback Handling

Native wallet presentations on both platforms are bounded by a generous timeout (default: 5 minutes, allowing ample time for user review):
- **Dart Implementation**: Both `addApplePass` and `addGooglePass` attach `.timeout(...)` with a clear timeout failure:
  `WalletProvisionFailure('Pass provisioning timed out waiting for the wallet.')`
- **Configurable / Injectable Duration**: `PlatformNativeWalletBridge` accepts `Duration? timeoutDuration` (defaulting to `Duration(minutes: 5)`), allowing unit tests to specify millisecond thresholds without flaky sleep pauses.
- **Late Result Immunity**:
  - On iOS, `methodFuture.ignore()` prevents unhandled asynchronous exceptions if the native channel responds after timeout.
  - On Android, `completer.isCompleted` guards inside `onSuccess`, `onCanceled`, and `onError` ensure any late callbacks from Google Play Services are dropped harmlessly with zero double-completion errors.

---

## 3. Defense-in-Depth: Stub Guard

Before any pass bytes or JWT tokens reach the native operating system layers, passes are evaluated by the stub guard in `wallet_provisioner.dart`:

1. **Apple Pass Inspection**:
   - HTTP response header check: `X-Pass-Stub: true`.
   - Binary archive inspection: Decodes ZIP structure in Dart using `archive` package. Verifies presence of a file named `signature`. If missing, the pass is an unsigned stub.
2. **Google Pass Inspection**:
   - HTTP response header check: `X-Pass-Stub: true`.
   - JSON body attribute: `stub: true`.
   - JWT header decode: Decodes header JSON without verifying signature, checking `alg` field. If `alg == 'none'` or missing, the pass is an unsigned stub.

**Outcome**: Any stub pass triggers `WalletProvisionStubError('Pass provisioning requires a signed pass from the issuer')` immediately. The native bridge and platform channels receive zero invocations.

---

## 4. User Experience & Result Types

`WalletProvisionResult` defines the following outcomes handled in `home_screen.dart`:

| Result Type | Hierarchy | UI Presentation | Meaning |
|---|---|---|---|
| `WalletProvisionSuccess` | `WalletProvisionResult` | SnackBar: "Pass added to wallet." | OS confirmed the pass was added to the wallet library. |
| `WalletProvisionCancelled` | `WalletProvisionResult` | Quiet (no SnackBar) | User dismissed the native presentation sheet without adding. |
| `WalletProvisionBusy` | `WalletProvisionResult` | Quiet (no SnackBar) | A pass addition request is already active in native code. |
| `WalletProvisionStubError` | `WalletProvisionResult` | SnackBar: "Pass provisioning requires a signed pass from the issuer" | Backend served an unsigned development stub. |
| `WalletProvisionUnavailable` | `WalletProvisionResult` | SnackBar: "Native wallet provisioning is not available in this build" | Device or platform does not support the native wallet sheet. |
| `WalletProvisionFailure` | `WalletProvisionResult` | SnackBar: failure message details | Corrupt pass, timeout (`'Pass provisioning timed out waiting for the wallet.'`), or platform exception. |

### Hierarchy Refactoring
Previously, `WalletProvisionCancelled` extended `WalletProvisionFailure`, causing `HomeScreen`'s failure pattern match to display an error SnackBar for normal user cancellations and obscuring compiler exhaustiveness checks. `WalletProvisionCancelled` is now a direct subclass of `WalletProvisionResult`. Both `WalletProvisionCancelled` and `WalletProvisionBusy` are handled as quiet outcomes without disturbing the user with error alerts.

### Debounce & Inline Loading Indicator in `HomeScreen`
`HomeScreen` tracks the active `_provisioningDocumentId`:
- While a document is provisioning, its card's 'Add to OS Wallet' button is disabled (`onPressed: null`).
- The button replaces its wallet icon with a compact `CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary)` using theme colors (zero hardcoded color literals).
- Synchronous check `if (_provisioningDocumentId != null) return;` at the beginning of `_handleAddToWallet` guarantees that rapid double-taps spawn exactly one provision request.
- The `finally` block guarantees `_provisioningDocumentId` is reset to `null` on all outcomes (success, cancel, busy, failure, timeout), re-enabling the button for future actions.

---

## 5. Apple PassKit & Entitlement Requirements

### Cryptographic Signing
Apple Wallet strictly requires every `.pkpass` bundle to be a ZIP archive containing:
1. `pass.json`: Canonical pass model schema.
2. Icon and image assets (`icon.png`, `icon@2x.png`, `logo.png`).
3. `manifest.json`: SHA-256 / SHA-1 checksums of every file in the bundle.
4. `signature`: PKCS#7 detached signature of `manifest.json` signed by an Apple-issued Pass Type ID certificate and intermediate WWDR G4 certificate.

### Entitlement Research: `containsPass(_:)`
- **Finding**: Calling `PKPassLibrary().containsPass(pass)` does **NOT** require the `com.apple.developer.pass-type-identifiers` entitlement.
- **Apple Specification**: Apple explicitly designed `containsPass(_:)` to allow distribution apps (such as airline, transit, or identity apps) to check if a specific pass held in memory is already in the library without granting permission to read, list, or inspect passes created by other issuers.
- **Entitlement Scope**: The `com.apple.developer.pass-type-identifiers` entitlement is only required when querying library-wide passes (`passes()`, `passes(of:)`, or `pass(withPassTypeIdentifier:serialNumber:)`).
- **Team ID Hygiene**: No entitlement file or `DEVELOPMENT_TEAM` identifier was added to `Runner.xcodeproj`, preserving scrubbed project configuration.

---

## 6. Google Wallet Requirements

- **Issuer Account**: An active Google Pay & Google Wallet Console issuer account.
- **Class and Object Model**: Pre-created Pass Class ID and Pass Object ID matching the driving license schema.
- **Cryptographic Signing**: Service account credentials producing RS256/ES256 signed JWTs with valid claims (`iss`, `aud: "google"`, `typ: "savetowallet"`, `payload`).
- **Android Manifest**: `<meta-data android:name="com.google.android.gms.wallet.api.enabled" android:value="true" />` in `AndroidManifest.xml`.

---

## 7. Verification Matrix: Verified vs. Unverified

### Verified by Automated Tests & Compiler Proofs
- **All Unit & Widget Tests Pass**: 97 tests pass cleanly via `flutter test --no-pub`.
- **Platform Channel Dispatch**: Faked channel tests verify:
  - Confirmed `true` -> `WalletProvisionSuccess`.
  - User cancelled `false` -> `WalletProvisionCancelled`.
  - Native `busy` PlatformException -> `WalletProvisionBusy`.
  - iOS timeout -> `WalletProvisionFailure('Pass provisioning timed out waiting for the wallet.')`.
  - Android timeout -> `WalletProvisionFailure('Pass provisioning timed out waiting for the wallet.')`.
  - Late native callbacks and errors -> ignored safely with no unhandled exceptions.
  - `invalid_pass` error code -> `WalletProvisionFailure` with explicit message.
  - `unavailable` -> `WalletProvisionUnavailable`.
- **UI Debounce & Widget Behavior**: Widget tests in `home_wallet_button_test.dart` verify:
  - Two rapid taps trigger exactly ONE provision call (`callCount == 1`).
  - Button disables and displays theme `CircularProgressIndicator` during in-flight operation.
  - Button re-enables on completion, failure, cancellation, and busy results.
  - `WalletProvisionCancelled` and `WalletProvisionBusy` produce zero error SnackBars.
- **Mutation Verification (3 Checks Reported)**:
  1. *Remove Dart timeout*: `wallet_provisioner_test.dart` test `'iOS method channel timeout yields WalletProvisionFailure'` hangs indefinitely until alarm aborts (SIGALRM 142). Restored.
  2. *Make Cancelled a Failure subclass again*: `wallet_provisioner_test.dart` test `'WalletProvisionCancelled is a direct subclass of WalletProvisionResult and not Failure'` fails (`Expected: not <Instance of 'WalletProvisionFailure'>, Actual: <Instance of 'WalletProvisionCancelled'>`) and `home_wallet_button_test.dart` test `'WalletProvisionCancelled does not show an error snackbar and re-enables button'` fails on unexpected SnackBar. Restored.
  3. *Remove UI debounce*: `home_wallet_button_test.dart` test `'two rapid taps trigger exactly one provision call and button re-enables afterwards'` fails (`Expected: <1>, Actual: <2>`). Restored.
- **Native iOS Compilation**: Succeeded in temporary directory via `flutter build ios --simulator --no-codesign` with `WalletChannelHandler.swift` (`✓ Built build/ios/iphonesimulator/Runner.app` in 36.0s).
- **Native Android Compilation**: Succeeded in temporary directory via `flutter build apk --debug` with `com.google.android.gms.wallet.api.enabled` in `AndroidManifest.xml` (`✓ Built build/app/outputs/flutter-apk/app-debug.apk` in 32.3s).

### Verified by Line-by-Line Code Review
- **Swift `WalletChannelHandler.swift`**:
  - `self.pendingResult == nil` re-entrancy guard returning `busy` error immediately.
  - Exactly-once `result(...)` invocation across all failure branches and dismiss delegate.
  - Immediate clearing of `self.pendingResult` and `self.pendingPass` preventing memory or callback leaks.

### NOT Verified (Hardware & Production Credential Constraints)
- **Real Physical Device Testing**: Real Face ID/Touch ID and Secure Enclave confirmation on a physical iPhone; real Google Pay sheet rendering on a physical Android device.
- **Real Apple PassKit Out-of-Process Sheets**: `PKAddPassesViewController` modal sheets are rendered out-of-process by the iOS SpringBoard/PassKit daemon and cannot be automated in headless unit tests.
- **Production Apple Signed Passes**: Requires an active Apple Developer Program certificate and private key to generate signed `.pkpass` bundles accepted by `PKPass(data:)`.
- **Production Google Wallet Service Account**: Requires a production Google Cloud Service Account key to sign JWTs for Google Wallet API.
