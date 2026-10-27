# Mobile Simulator Integration Tests

End-to-end security and document verification integration test suite for the Identity Wallet application.

## Running the Integration Test

The automated runner script bootstraps a private backend, configures an admin, creates a QA user, issues a driving license, boots an iOS simulator, and executes the integration test suite.

View help and all available options:

```bash
mobile/tool/run_integration_test.sh --help
```

### Standard Execution

Run directly using default options (starts private backend on port 3170, creates a temporary iPhone 16 simulator, runs tests, and cleans up):

```bash
mobile/tool/run_integration_test.sh
```

### Running Against an Isolated Copy

To prevent xcodebuild and Flutter build artifacts from modifying the workspace repository:

```bash
TMP_DIR=$(mktemp -d)
rsync -a --exclude build --exclude .dart_tool --exclude ios/Pods mobile/ "$TMP_DIR/mobile_copy/"
MOBILE_DIR="$TMP_DIR/mobile_copy" mobile/tool/run_integration_test.sh
rm -rf "$TMP_DIR"
```

### Options and Environment Variables

- `--port <port>`: Port for the private backend instance (default: `3170`).
- `--device <udid>`: UDID of an existing simulator to target. When omitted, the runner creates a dedicated iPhone 16 simulator.
- `--keep-simulator`: Prevents deletion of the created simulator upon test completion.
- `--timeout <seconds>`: Overall execution timeout enforced by a process alarm (default: `900` seconds / 15 minutes).
- `MOBILE_DIR`: Environment variable specifying the mobile project root directory (default: `mobile/` in repo).

## What Is Proven by This Test

1. **Authentication Lifecycle**:
   - Clean login with QA credentials against real backend endpoints (`/api/auth/sign-in/email`).
   - Secure bearer token persistence in platform secure storage.
   - Clean sign out purging session credentials.
   - Account registration (`/api/auth/sign-up/email`) with a unique `qa+<timestamp>@...` email address and immediate authenticated session creation.

2. **Automatic Cryptographic Storage**:
   - Newly fetched documents are automatically encrypted and persisted to disk without manual "Save Offline" action.
   - On-disk ciphertext files use the envelope format starting with version byte `0x02`.
   - File contents on disk are verified to contain zero plaintext bytes of the document holder name (`QA User`).

3. **Biometric Access Gate**:
   - Biometric rejection prevents document decryption; the viewer remains inaccessible and no plaintext is exposed.
   - Biometric grant successfully decrypts and renders credential details in `DocumentViewerScreen`.

4. **In-Memory Zeroization on Route Pop**:
   - When navigating back from `DocumentViewerScreen`, the decrypted notifier state is cleared and verified null.
   - Plaintext document fields are completely removed from the widget tree.

5. **Lifecycle Backgrounding Lock**:
   - Dispatching `AppLifecycleState.paused` immediately clears decrypted document buffers in memory.
   - Resuming (`AppLifecycleState.resumed`) displays the `DocumentLocked` view requiring re-authentication.

6. **Offline Viewing Without Network Calls**:
   - With network requests blocked via a toggleable HTTP client throwing socket exceptions, unlocking the stored document succeeds using local encrypted storage and encryption keys.
   - Network call counter proves zero HTTP requests were initiated during offline unlock and viewing.

7. **Sign-Out Cryptographic Purge**:
   - Signing out purges the auth token, the encryption key from secure storage, and deletes all `.enc` document files from application support storage.

## What a Simulator CANNOT Prove

Simulators run in a software-emulated environment and cannot validate hardware-enforced guarantees:

1. **Hardware Biometrics**:
   - Simulators do not execute real Touch ID, Face ID, or BiometricPrompt hardware sensors. Biometric authentication in this test is driven via an authorized controllable fake (`ControllableBiometricAuthService`).
2. **Hardware-Backed Keystores**:
   - Secure Enclave (Apple) and Android Keystore StrongBox hardware key isolation cannot be exercised inside a simulator runtime.
3. **Screen Security (FLAG_SECURE)**:
   - Android window protection (`FLAG_SECURE`) against screenshots and screen recorders cannot be verified on iOS simulators.
4. **iOS Multitasking Snapshot Privacy**:
   - Obscuring the application window in the iOS app-switcher tray with a privacy blur or custom cover screen cannot be evaluated inside headless/simulator test harnesses.
5. **Backup Exclusion Attributes**:
   - File system attributes such as `NSURLIsExcludedFromBackupKey` require inspection of real iOS backup manifests.
6. **Native Wallet Presentation**:
   - Native Apple Wallet (`PKAddPassesViewController`) and Google Wallet native provisioning sheets require real system services and device entitlements.

## iOS App Transport Security (ATS) Note

Local connections to `localhost` and `127.0.0.1` on any port are exempt from Apple App Transport Security (ATS) restrictions. The integration test backend runs over plaintext HTTP on `http://localhost:3170` without needing `NSAppTransportSecurity` exceptions or modifications to `Info.plist`.
