# Mobile Identity Wallet

A Flutter mobile application for secure identity credential management, offline encrypted document storage, biometric viewing gates, and digital wallet provisioning.

---

## 1. How to Run

### Prerequisites
- **Flutter SDK**: 3.29.x / 3.41.x or compatible Dart 3.x runtime.
- **iOS Simulator**: Xcode 16+ with iOS 18+ simulator.
- **Android Emulator**: Android SDK with API 34+ emulator.
- **Backend Service**: An active backend instance running at `http://localhost:3000` (for local development and integration tests).

### Configuration Flags
- **`API_BASE_URL`**: Target backend base URL.
  - iOS Simulator: `http://localhost:3000` (shares the macOS host network namespace directly).
  - Android Emulator: `http://10.0.2.2:3000` (maps to host loopback `127.0.0.1:3000`).
  - Production / Release: `https://api.wallet.example.com` (enforced by scheme validation; `http://` is strictly prohibited in release mode).
- **`OS_BOUND_KEY`**: Compile-time boolean flag (`--dart-define=OS_BOUND_KEY=true`, default: `false`).
  - When enabled, `flutter_secure_storage` protects the master encryption key using OS-level biometric constraints (`biometryCurrentSet` and `userPresence` flags on iOS Keychain; `AndroidOptions.biometric` on Android).
  - Unverified on physical hardware. See [`SECURITY.md`](SECURITY.md) for key names, migration semantics, and invalidation recovery.

### Run on iOS Simulator
1. List available simulators and find your target UDID:
   ```bash
   xcrun simctl list devices available
   ```
2. Boot the simulator (e.g., iPhone 16):
   ```bash
   xcrun simctl boot <SIMULATOR_UDID>
   ```
3. Run the application:
   ```bash
   cd mobile
   flutter run -d <SIMULATOR_UDID> --dart-define=API_BASE_URL=http://localhost:3000
   ```
   To enable OS-bound biometric key release:
   ```bash
   flutter run -d <SIMULATOR_UDID> --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=OS_BOUND_KEY=true
   ```

### Run on Android Emulator
1. Start an Android Virtual Device (AVD).
2. Run the application:
   ```bash
   cd mobile
   flutter run -d <EMULATOR_DEVICE_ID> --dart-define=API_BASE_URL=http://10.0.2.2:3000
   ```
   To enable OS-bound biometric key release:
   ```bash
   flutter run -d <EMULATOR_DEVICE_ID> --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=OS_BOUND_KEY=true
   ```

---

## 2. Key Mobile Flows

### User Registration & Authentication
- **Login Screen (`LoginScreen`)**: Authenticates via email and password (`POST /api/auth/sign-in/email`). Extracts session token from the `set-auth-token` header and stores it in secure storage. All password fields are always obscured (`obscureText: true`).
- **Create Account Screen (`CreateAccountScreen`)**: Registers a new account with full name, valid email, password (8–128 characters), and matching password confirmation (`POST /api/auth/sign-up/email`). Password fields are always obscured. Upon success, the session token is saved and the user is immediately authenticated.

### Automatic Encrypted Storage (Auto-Store)
- When `loadDocuments` fetches identity credentials from the backend, it automatically inspects local storage. Any issued document not yet stored locally is automatically downloaded, encrypted via AES-256-GCM (with a unique 12-byte IV and AAD bound to `wallet-doc:v2:$documentId`), and written to the Application Support directory (`doc_<id>.enc`).
- Once saved, documents display the "Stored offline" badge in the list.
- A single biometric prompt covers the entire batch when an encryption key exists; if no key exists yet, one is generated and stored without a biometric prompt. In-flight loads are serialized via an internal Future guard.

---

## 3. Test Execution & Verification Matrix

### Unit and Widget Tests
Execute all unit and widget tests:
```bash
cd mobile
flutter test
```

#### What Unit Tests Verify
- **`api_client_test.dart`**:
  - `POST /api/auth/sign-in/email`: Successful sign-in, extraction of token from `set-auth-token` header.
  - `POST /api/auth/sign-up/email`: Successful sign-up, extraction of token from `set-auth-token` header.
  - Error responses: 400 Bad Request, 401 Unauthorized, 422 User Already Exists mapping to `ApiException`.
  - Security policies: Prohibition of `http://` scheme in release mode (`StateError`); prohibition of HTTP redirects on authenticated requests (`followRedirects = false`).
  - Document operations: Listing documents (`GET /api/documents`) and fetching document details (`GET /api/documents/:id`).
- **`crypto_service_test.dart`**:
  - AES-256-GCM encryption and decryption.
  - Binary envelope v2 format validation: Byte 0 is `0x02`, bytes 1–12 are IV, bytes 13–28 are GCM tag, bytes 29+ are ciphertext.
  - Unique IV generation per encryption operation.
  - Additional Authenticated Data (AAD) binding using `wallet-doc:v2:$documentId`.
  - Rejection of tampered ciphertext, altered IV, or manipulated auth tag (`CryptoAuthenticationException`).
  - Rejection of mismatched document ID in AAD (`CryptoAuthenticationException`).
  - Rejection of v1 legacy envelope format (`InvalidEnvelopeVersionException`).
  - Key memory wiping (`Uint8List.fillRange(0, length, 0)`).
- **`encrypted_file_storage_test.dart`**:
  - Document ID validation and path traversal defense (strict regex `^[A-Za-z0-9_-]{1,128}$`).
  - Rejection of traversal attempts (`../`, `/`, `\`).
  - Writing encrypted envelopes to the Application Support directory.
  - Reading and deleting encrypted envelopes.
  - Purging all stored files on user sign-out.
- **`biometric_key_provider_test.dart`**:
  - Key generation on first use without biometric prompt.
  - App-level biometric gating via `local_auth` when `OS_BOUND_KEY` is false.
  - OS-bound key release when `OS_BOUND_KEY` is true.
  - Platform exception mapping (`keyInvalidated`, `notEnrolled`, `lockedOut`, `canceled`, `unsupported`).
- **`theme_mode_provider_test.dart`**:
  - Theme toggling between light, dark, and system modes.

#### What Widget Tests Verify
- **`login_screen_test.dart`**:
  - Form validation: Required email format and non-empty password.
  - Form submission calling `AuthNotifier.signIn`.
  - Display of 401 invalid credentials error banner.
  - Navigation button to Create Account screen.
  - Password field always obscured (`obscureText: true`).
- **`create_account_screen_test.dart`**:
  - Form validation: Non-empty name, valid email, 8-128 character password, password confirmation matching.
  - Form submission calling `AuthNotifier.signUp`.
  - Display of 422 'User already exists' error message.
  - Display of 400 validation error message.
  - Link returning back to Login screen.
  - Password and confirm-password fields always obscured (`obscureText: true`).
- **`home_screen_test.dart`**:
  - Document list display (e.g., Driving License).
  - Offline badge display for locally stored documents.
  - Sign out button triggering session purge.
  - Theme toggle button.
- **`home_wallet_button_test.dart`**:
  - Debounce: two rapid taps trigger exactly one provision call.
  - Button disables and shows inline progress indicator during operation.
  - Button re-enables on success, cancellation, busy, and failure.
  - Quiet cancellation and busy results produce zero error SnackBars.
- **`document_viewer_screen_test.dart`**:
  - Biometric gate prompt on entry.
  - Presentation of decrypted identity fields (Full Name, License Number, Expiry Date, Categories) upon successful authentication.
  - Locked state presentation upon authentication failure or cancellation.
  - Synchronous buffer zeroing on screen disposal with deferred state reset.
  - Immediate state clear and buffer zeroing on app backgrounding (`paused`, `inactive`, `hidden`).

---

### End-to-End Integration Tests on iOS Simulator
Execute the complete security and credential lifecycle flow against a private backend instance:

```bash
# Automated runner (starts private backend, boots simulator, executes test, cleans up):
mobile/tool/run_integration_test.sh

# Or inspect options:
mobile/tool/run_integration_test.sh --help
```

To run against an isolated mobile copy so Xcode build artifacts do not modify the workspace:
```bash
TMP_DIR=$(mktemp -d)
rsync -a --exclude build --exclude .dart_tool --exclude ios/Pods mobile/ "$TMP_DIR/mobile_copy/"
MOBILE_DIR="$TMP_DIR/mobile_copy" mobile/tool/run_integration_test.sh
rm -rf "$TMP_DIR"
```

Configuration variables supported by `run_integration_test.sh`:
- `--port <port>`: Port for the private backend instance (default: `3170`).
- `--device <udid>`: UDID of an existing simulator to target. When omitted, creates a dedicated iPhone 16 simulator.
- `--keep-simulator`: Prevents deletion of the created simulator upon completion.
- `--timeout <seconds>`: Overall execution deadline enforced by alarm (default: `900` seconds / 15 minutes).
- `SIM_RUNTIME`: Environment variable specifying the iOS simulator runtime (default: newest installed runtime, e.g. `com.apple.CoreSimulator.SimRuntime.iOS-18-3`; verified on iOS 18.3).
- `MOBILE_DIR`: Path to the mobile project root directory.

#### What the Integration Test Verifies

The integration test suite (`mobile/integration_test/e2e_faked_biometrics_simulator_test.dart`) has completed real automated runs on an iOS 18.3 simulator against a private backend. It executes and asserts:

- **Live Authentication**: Signs in against the running backend with QA credentials (`POST /api/auth/sign-in/email`).
- **Remote Document Fetching**: Retrieves issued driving license details from the backend.
- **Automatic Encrypted Storage (Auto-Store)**: Automatically encrypts the fetched document on-device and persists it to Application Support storage; reads raw on-disk bytes and verifies:
  1. Envelope starts with version byte `0x02`.
  2. Byte stream contains zero occurrences of plaintext holder name (`QA User`).
- **Biometric Access Gate**: Rejection by `ControllableBiometricAuthService` keeps the viewer closed, leaves the decrypted notifier null, and displays no plaintext.
- **Offline Viewing Without Network Calls**: With network blocked via `ToggleableHttpClient` (throwing socket exceptions), biometric grant unlocks the document, renders decrypted fields ('Full Name', 'QA User'), and verifies 0 network requests were initiated.
- **In-Memory Zeroing on Navigation**: Exiting `DocumentViewerScreen` via the back button resets `decryptedDocumentNotifierProvider` to null.
- **Lifecycle Inactivity Wipe**: Reopening the document and dispatching `AppLifecycleState.paused` immediately clears decrypted document buffers in memory; resuming displays the 'Document Locked' view.
- **Biometric Re-Unlock While Offline**: Re-unlocking while offline verifies rejection maintains the lock, while grant decrypts and displays fields with 0 network calls.
- **Complete Session Purge on Sign Out**: Tapping Sign Out purges the bearer token and master encryption key from secure storage, and deletes all `.enc` files from the Application Support directory.
- **Live Account Registration**: Navigates to Create Account screen, registers a new user with a unique timestamped email (`qa+<timestamp>@wallet.local`), verifies automated sign-in, token storage, and key generation, followed by clean sign-out.

---

## 4. Platform Limitations: What Is NOT Verified

The automated test suite verifies application logic, encryption algorithms, lifecycle hooks, and filesystem operations. However, the following platform-level security capabilities cannot be verified in simulator automation:

1. **Hardware-Enforced Biometrics (Face ID / BiometricPrompt)**:
   - iOS Simulators and standard emulators do not possess Secure Enclave Processor (SEP) or Trusted Execution Environment (TEE) hardware.
   - Simulator runs use `ControllableBiometricAuthService` to simulate success and failure paths. Real hardware biometric enrollment, sensor capture, and OS biometric lockout require physical device testing.
2. **Android `FLAG_SECURE`**:
   - `MainActivity.kt` configures `WindowManager.LayoutParams.FLAG_SECURE` to blank out the app in the recent apps task switcher and block OS-level screenshots.
   - Flutter integration tests operate within the app process and cannot inspect OS-level window compositor frames.
3. **iOS App Switcher Privacy Snapshot Cover**:
   - `SceneDelegate.swift` and `AppDelegate.swift` display a full-screen privacy cover overlay when `sceneWillResignActive` or `applicationWillResignActive` fires, removing it on `sceneDidBecomeActive`.
   - The OS task switcher snapshot capture is an operating system mechanism that cannot be programmatically captured through Flutter test drivers.
4. **`NSURLIsExcludedFromBackupKey` OS Enforcement**:
   - The native platform channel (`com.example.wallet_app/backup_exclusion`) applies the `NSURLIsExcludedFromBackupKey` filesystem attribute to the Application Support directory.
   - Verification that Apple iCloud and iTunes backup daemons honor this flag requires performing an actual device backup and examining backup manifests.
5. **Native OS Wallet Presentation Sheets**:
   - Adding passes to Apple Wallet or Google Wallet displays system modal UI managed out-of-process by PassKit or Google Play Services.
   - Flutter test drivers cannot interact with or assert on out-of-process OS modal sheets.

---

## 5. Native OS Wallet Passes & Architecture

The application provides an "Add to Apple / Google Wallet" feature backed by `PlatformNativeWalletBridge`, `AppleWalletProvisioner`, and `GoogleWalletProvisioner`.

### Pass Architecture & Verification
1. **Apple PassKit**:
   - Native presentation is handled by `WalletChannelHandler.swift` over the `com.example.wallet_app/wallet` channel, delegating to `PKAddPassesViewController`.
   - Pass addition confirmation is queried via `PKPassLibrary().containsPass(pass)`.
2. **Google Wallet**:
   - Native presentation is handled via the `add_to_google_wallet` plugin on Android devices.
3. **Defensive Stub Guard**:
   - The mobile provisioner inspects incoming pass payloads before invoking native platform channels.
   - Apple passes are checked for `X-Pass-Stub: true` or missing `signature` archive entries in the `.pkpass` ZIP.
   - Google passes are checked for `X-Pass-Stub: true`, `stub: true`, or `alg: none` JWT headers.
   - Detected stubs trigger `WalletProvisionStubError`, presenting an informative message without invoking native channels.
4. **Backend Signed Pass Support**:
   - When server credentials are configured in `backend/.env`, the backend emits cryptographically signed passes (`X-Pass-Stub: false`): Apple `.pkpass` packages signed with PKCS#7 via `pkijs`/`asn1js`, and RS256-signed JWTs for Google Wallet. See [`WALLET.md`](WALLET.md) and [`SECURITY.md`](SECURITY.md).
