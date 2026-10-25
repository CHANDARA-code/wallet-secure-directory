# Mobile Identity Wallet

A Flutter mobile application for secure identity credential management, offline encrypted document storage, biometric viewing gates, and digital wallet provisioning.

---

## 1. How to Run

### Prerequisites
- **Flutter SDK**: 3.29.x / 3.41.x or compatible Dart 3.x runtime.
- **iOS Simulator**: Xcode 16+ with iOS 18+ simulator.
- **Android Emulator**: Android SDK with API 34+ emulator.
- **Backend Service**: An active backend instance running at `http://localhost:3000` (for local development and integration tests).

### Base URL Configuration
- **iOS Simulator**: `http://localhost:3000` (shares the macOS host network namespace directly).
- **Android Emulator**: `http://10.0.2.2:3000` (maps to host loopback `127.0.0.1:3000`).
- **Production / Release**: `https://api.wallet.example.com` (enforced by scheme validation; `http://` is strictly prohibited in release mode).

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

### Run on Android Emulator
1. Start an Android Virtual Device (AVD).
2. Run the application:
   ```bash
   cd mobile
   flutter run -d <EMULATOR_DEVICE_ID> --dart-define=API_BASE_URL=http://10.0.2.2:3000
   ```

---

## 2. Test Execution & Verification Matrix

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
- **`theme_mode_provider_test.dart`**:
  - Theme toggling between light, dark, and system modes.

#### What Widget Tests Verify
- **`login_screen_test.dart`**:
  - Form validation: Required email format and non-empty password.
  - Form submission calling `AuthNotifier.signIn`.
  - Display of 401 invalid credentials error banner.
  - Navigation button to Create Account screen.
- **`create_account_screen_test.dart`**:
  - Form validation: Non-empty name, valid email, 8-128 character password, password confirmation matching.
  - Form submission calling `AuthNotifier.signUp`.
  - Display of 422 'User already exists' error message.
  - Display of 400 validation error message.
  - Link returning back to Login screen.
- **`home_screen_test.dart`**:
  - Document list display (e.g., Driving License).
  - Offline badge display for locally stored documents.
  - Sign out button triggering session purge.
  - Theme toggle button.
- **`document_viewer_screen_test.dart`**:
  - Biometric gate prompt on entry.
  - Presentation of decrypted identity fields (Full Name, License Number, Expiry Date, Categories) upon successful authentication.
  - Locked state presentation upon authentication failure or cancellation.
  - Explicit notifier clearing on screen disposal.

---

### End-to-End Integration Tests on iOS Simulator
Execute the complete security and credential lifecycle flow against a running backend:
```bash
cd mobile
flutter test integration_test \
  -d <SIMULATOR_UDID> \
  --dart-define=API_BASE_URL=http://localhost:3000 \
  --dart-define=QA_EMAIL=qa@wallet.local \
  --dart-define=QA_PASSWORD=<QA_PASSWORD>
```

#### What the Integration Test Is Written To Verify

> **Status: not yet verified.** This test was written and the app was built and installed on an iOS simulator, but the run did not finish: the authoring task timed out after 60 minutes while waiting for it. Treat the list below as the intended coverage until a full run has passed.

- **Live Authentication**: Signs in against the running backend with QA credentials.
- **Remote Document Fetching**: Retrieves issued driving license details from the backend.
- **Encrypted Local Storage**: Saves the document offline; reads raw bytes from the Application Support directory and verifies:
  1. File starts with envelope version `0x02`.
  2. File does not contain plaintext name bytes ('QA User') anywhere in the byte stream.
- **Biometric Unlock**: Unlocks the document via `ControllableBiometricAuthService` and renders decrypted fields.
- **Memory Zeroing on Navigation**: Exits viewer screen and confirms `decryptedDocumentNotifierProvider` is reset to null.
- **Lifecycle Inactivity Wipe**: Re-opens document viewer and transitions app lifecycle to `AppLifecycleState.paused` (backgrounded); verifies the notifier state is immediately wiped to null and the screen displays 'Document Locked'.
- **Biometric Rejection Handling**: Denies biometric authentication; confirms document remains locked with zero plaintext displayed.
- **Complete Session Purge on Sign Out**: Taps Sign Out and confirms:
  1. Bearer token is erased from `flutter_secure_storage`.
  2. Master encryption key is erased from `flutter_secure_storage`.
  3. All `.enc` ciphertext files are deleted from the Application Support directory.
- **Live Account Creation**: Navigates to Create Account screen, registers a new user with a unique timestamped email (`qa+<timestamp>@wallet.local`), verifies automated sign-in and key generation, and performs a clean sign-out.

---

## 3. Platform Limitations: What Is NOT Verified

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

## 4. Apple Wallet PassKit Requirements

The application provides an "Add to Apple Wallet" feature backed by `AppleWalletProvisioner` and `WalletProvisioner`.

### PassKit Architecture Requirements
1. **Pass Signature**:
   - Apple Wallet (`PKPassLibrary.addPasses`) strictly requires a valid `.pkpass` bundle containing:
     - `pass.json` (pass definition and metadata)
     - Manifest file `manifest.json` (SHA-1/SHA-256 hashes of all bundle files)
     - Cryptographic signature `signature` (DER-encoded PKCS#7 signature signed by an Apple-issued Pass Type ID certificate)
2. **Entitlements**:
   - The iOS application bundle must have the `com.apple.developer.pass-type-identifiers` entitlement configured in its provisioning profile matching the Pass Type ID.
3. **Backend Stub Passes**:
   - The current development backend issues unsigned stub passes tagged with the HTTP header `X-Pass-Stub: true`.
   - `AppleWalletProvisioner` inspects incoming `.pkpass` files for the `X-Pass-Stub: true` header and confirms the presence of a valid `signature` archive entry.
   - When a stub is detected, `AppleWalletProvisioner` returns `WalletProvisionStubError`, and the UI displays an informative message rather than passing an invalid bundle to PassKit.
