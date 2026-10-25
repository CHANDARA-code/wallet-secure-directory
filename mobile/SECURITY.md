# Mobile Wallet Security Architecture & Limitations

## 1. Cryptographic Architecture

### Key Lifecycle and Storage
- **Algorithm**: AES-256 in Galois/Counter Mode (AES-GCM).
- **Key Generation**: 32-byte (256-bit) cryptographically secure random keys are generated on-device using Dart's CSPRNG `Random.secure()`.
- **First-Time Provisioning**: Key existence is checked via a non-secret-returning existence check (`hasKey()`). If no key exists in secure storage, a key is generated with `Random.secure()`, written to secure storage, and returned without prompting for biometrics since no existing secret is being released.
- **Biometric Key Gating**: Once an encryption key exists, every subsequent retrieval from secure storage must be authorized through `BiometricKeyProvider` via biometric authentication (`biometricOnly: true`).
- **Authentication Separation**: The `signIn` flow does not read the encryption key. Document viewing (`unlockDocument`) gates the entire flow on biometric authentication before any file or network caching occurs.
- **In-Memory Zeroing**: Active key byte arrays (`Uint8List`) in memory are zeroed (`fillRange(0, length, 0)`) immediately after encryption and decryption within `finally` blocks to minimize exposure in heap memory.
- **Key Storage**: Keys are never hardcoded and never persisted to plain storage (`SharedPreferences` / `NSUserDefaults`). The encryption key is stored exclusively in `flutter_secure_storage`, which bridges to Android Keystore and iOS Keychain.
- **Platform Configuration**:
  - **iOS**: Configured with `KeychainAccessibility.first_unlock_this_device` and `synchronizable: false` (no iCloud Keychain synchronization).
  - **Android**: Configured with `KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding`, `StorageCipherAlgorithm.AES_GCM_NoPadding`, and `resetOnError: true`.

### Encryption and Versioned Envelope with AAD Binding
- **Fresh IV**: Every encryption operation generates a unique 12-byte (96-bit) Initialization Vector (IV) from `Random.secure()`. IVs are never reused.
- **Additional Authenticated Data (AAD)**: AES-256-GCM binds the `documentId` as authenticated data (`wallet-doc:v2:$documentId`). This prevents ciphertext swap attacks across different documents encrypted under the same master key. Decrypting a ciphertext with a mismatched `documentId` fails AEAD authentication.
- **Envelope Version 2**: Ciphertext is stored in a versioned binary envelope:
  - Byte 0: Envelope version (`0x02`).
  - Bytes 1–12: 12-byte IV.
  - Bytes 13–28: 16-byte GCM authentication tag.
  - Bytes 29+: Ciphertext payload.
- **Legacy Envelope Migration**: Version-1 envelopes fail version checks with `InvalidEnvelopeVersionException`. The application catches this in the document viewing flow, purges the outdated local file, and refetches fresh data from the server rather than crashing.
- **Integrity & Tamper Resistance**: Any tampering with ciphertext bytes, the IV, the GCM tag, or the bound `documentId` causes authentication verification to fail immediately. PointyCastle's AEAD validation throws an authentication error mapped to `CryptoAuthenticationException`. Decryption never yields partial or unauthenticated plaintext.

---

## 2. Authentication: App-Level Biometric Gate vs. OS-Enforced Key Binding

### The App-Level Gate Implementation
The application uses the `local_auth` package to prompt the user for biometric authentication (`biometricOnly: true`) before requesting an existing decryption key from secure storage. If biometric authentication fails, is canceled, is unsupported, or encounters lockout/not-enrolled states, the key is never requested from storage and never released to memory.

### Limitations of App-Level Biometric Gating
A `local_auth` check executed in Dart/Flutter application code is an **application-level gate**, not an OS-enforced cryptographic key release:
1. The decryption key itself stored in Keystore/Keychain is not hardware-bound to the user's biometric state by the OS.
2. If the application runtime is compromised (e.g., on a rooted or jailbroken device, or via dynamic instrumentation like Frida), the application-level boolean check can theoretically be bypassed to read from secure storage directly.

### What OS-Bound Keys Would Add
True hardware-backed cryptographic protection requires the operating system's Secure Element / TEE to gate key release directly:
- **Android Keystore**: Using `KeyGenParameterSpec.Builder.setUserAuthenticationRequired(true)` binds the cryptographic key directly to biometric authentication. The Keymaster/Keymint TEE hardware refuses to perform cryptographic operations (or release key material) without a valid biometric authentication token from the OS biometric daemon.
- **iOS Keychain**: Using `SecAccessControlCreateWithFlags` with `.biometryCurrentSet` or `.biometryAny` combined with `.userPresence` ensures the Keychain item is guarded by the Secure Enclave. The item cannot be decrypted without local Touch ID/Face ID authentication verified by the Secure Enclave Processor (SEP).

### Capabilities of `flutter_secure_storage` (v11.2.0)
The installed version of `flutter_secure_storage` (v11.2.0) exposes certain biometric parameters on Android:
- `AndroidOptions(enforceBiometrics: true, requireBiometricsPerOperation: true)`.
However, on iOS, `IOSOptions` only provides accessibility flags (`first_unlock_this_device`) and `useSecureEnclave: bool`, but does not expose fine-grained `SecAccessControl` constraints (such as `kSecAccessControlBiometryCurrentSet`) with seamless Flutter platform callbacks. Consequently, relying on a unified cross-platform app-level gate backed by `local_auth` is required to handle explicit fallback states (e.g., `notEnrolled`, `lockedOut`, `canceled`, `unsupported`) consistently across platforms while maintaining secure Keystore/Keychain storage.

---

## 3. Local Storage, Path Traversal Defense, & Backup Exclusion

### Path Sanitization
- All document identifiers are validated against the strict regex `^[A-Za-z0-9_-]{1,128}$` in both `IoEncryptedFileStorage` and `ApiClient`. Any input containing directory traversal patterns (`../`, `/`, `\`) or invalid characters is rejected with an `ArgumentError`.
- In `ApiClient`, identifiers are also passed through `Uri.encodeComponent` as defense-in-depth.

### Storage Location & iCloud/iTunes Backup Exclusion
- Local encrypted files are stored in the application support directory (`getApplicationSupportDirectory()`).
- On iOS, files in the support directory are excluded from cloud and local backups by setting `NSURLIsExcludedFromBackupKey` on the directory via a native platform channel (`com.example.wallet_app/backup_exclusion`).
- On initial read of a document, if a legacy file exists in the documents directory (`getApplicationDocumentsDirectory()`), it is deleted as outdated.
- On Android, `android:allowBackup="false"` is enforced in `AndroidManifest.xml`.

---

## 4. In-Memory Hygiene & Dart String Immutability

### Plaintext Lifecycle & Disposal
- Decrypted identity document payloads are held in `DecryptedDocumentNotifier`, a Riverpod state notifier with a nullable state (`DecryptedDocument?`).
- Plaintext data is managed as `Uint8List` byte buffers.
- When `DocumentViewerScreen` is disposed, or when the application lifecycle transitions to `AppLifecycleState.inactive`, `paused`, or `hidden`, the notifier clears its state (`state = null`) and overwrites every byte of the managed `Uint8List` with `0x00`.

### Dart String Immutability Limitation
In Dart, instances of `String` are immutable objects allocated on the managed garbage-collected heap:
1. Once a `String` is allocated (e.g., decoding UTF-8 JSON or displaying text in Flutter widgets), Dart provides no language mechanism to overwrite the underlying character buffer with zeroes.
2. The string remains in memory until the garbage collector runs and the heap page is reused.
3. Plaintext is preserved as `Uint8List` until parsing, references are promptly discarded, and sensitive fields are never logged.

---

## 5. Token & Secrets Hygiene

- **Logging**: Authentication bearer tokens, cryptographic keys, plaintexts, and ciphertexts are never logged via `print`, `debugPrint`, or logging frameworks.
- **Session Purge on Logout**: Upon logout, the application:
  1. Deletes all locally stored encrypted document files (`doc_*.enc`).
  2. Clears the encryption key from secure storage.
  3. Clears the bearer authentication token from secure storage.
  4. Resets all in-memory notifiers and zeroes active decrypted byte arrays.
- **All-or-Nothing Sign-In**: In `AuthNotifier.signIn`, token and initial key persistence is atomic; if key generation or storage fails, the token is deleted and an error is surfaced.

---

## 6. Network Security & Scheme Validation

- **Release Scheme Enforcement**: In release mode (`kReleaseMode`), `resolveBaseUrl` and `ApiClient` require an `https://` base URL and throw a `StateError` if configured with `http://`. Debug and profile modes permit local `http://` development defaults.
- **No HTTP Redirects on Authenticated Requests**: Authenticated HTTP requests set `followRedirects = false` via `http.Request`. If an authenticated request receives an HTTP 3xx redirect status code, it is rejected with an `ApiException` to prevent bearer tokens from leaking across unencrypted or unauthorized endpoints.

---

## 7. Native OS Wallet Passes & Status

- **Architecture**: The app interfaces with native wallets through `WalletProvisioner` and a `NativeWalletBridge` interface (`GoogleWalletProvisioner` and `AppleWalletProvisioner`).
- **Native Wallet Status in This Build**: Native OS wallet provisioning is not integrated in this build (`UnavailableNativeWalletBridge`). Calling provision on non-stub passes yields `WalletProvisionUnavailable('Native wallet provisioning is not available in this build')`, and the UI displays this honest status message. The app never reports `WalletProvisionSuccess` without confirmation from a native bridge.
- **Stub Detection Defense-in-Depth**:
  - **Apple Pass**: Inspected for the `X-Pass-Stub: true` header OR verified that the `.pkpass` ZIP archive contains a valid `signature` entry. If no `signature` is found in the ZIP archive, the pass is treated as an unsigned stub (`WalletProvisionStubError`).
  - **Google Pass**: Inspected for the `X-Pass-Stub: true` header, `stub: true` JSON body, OR a JWT header with `alg: none`. Any of these conditions triggers `WalletProvisionStubError`.

---

## 8. Screen Protection & OS Snapshots

- **Android**: `MainActivity` enables `WindowManager.LayoutParams.FLAG_SECURE` in `onCreate` to prevent screen capture, screen recording, and exposure in recent task snapshots.
- **iOS**: `SceneDelegate` and `AppDelegate` add a privacy cover view when the app transitions to inactive (`sceneWillResignActive` / `applicationWillResignActive`) and remove it upon becoming active (`sceneDidBecomeActive` / `applicationDidBecomeActive`).

---

## 9. Release Signing Security (SEC-11)

- In `android/app/build.gradle.kts`, the release build configuration currently uses the debug signing key (`signingConfigs.getByName("debug")`).
- **Action Required Before Production Shipping**: This must be replaced with a secure production release keystore (e.g. configured via environment variables or a secure CI secret store) before releasing the application to the Play Store or end users.

---

## 10. Execution Flags & Environment Endpoints

- **iOS Simulator Base URL**: `http://localhost:3000` (shares macOS host network namespace directly).
- **Android Emulator Base URL**: `http://10.0.2.2:3000` (routes to host `127.0.0.1:3000`).
- **Production URL**: Strict `https://` required in release mode.
- **Run Flags**:
  - `flutter run -d <device-id> --dart-define=API_BASE_URL=<url>`
- **Integration Test Flags**:
  - `flutter test integration_test -d <device-id> --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=QA_EMAIL=<email> --dart-define=QA_PASSWORD=<password>`

---

## 11. Security Verification Matrix: Verified vs. Unverified

### Verified by Automated Tests
- **Crypto & Envelope v2**: AES-256-GCM encryption/decryption, unique 12-byte IV per write, 16-byte authentication tag, AAD document ID binding (`wallet-doc:v2:$documentId`), rejection of tampered ciphertext/tag/IV, rejection of legacy v1 envelopes, and zeroing of key byte arrays in memory (`Uint8List.fillRange(0, length, 0)`).
- **Filesystem Traversal Defense**: Strict document ID regex validation (`^[A-Za-z0-9_-]{1,128}$`), blocking directory traversal attacks (`../`, `/`, `\`). Envelopes written to Application Support directory.
- **Plaintext Confidentiality on Disk**: Covered only by the unit tests of the crypto service and file storage. The simulator integration test that would also inspect real on-disk bytes (`integration_test/`) has been written but has not completed a run yet, so it is not counted as verification.
- **In-Memory Hygiene & Lifecycle Wipe**: `DecryptedDocumentNotifier` resets to null and zeroes underlying bytes on widget disposal, navigation pop, or when the application transitions to `AppLifecycleState.paused` (backgrounded).
- **Authentication & Atomic Storage**: Token and key generation on sign-in/sign-up are atomic; failure deletes the token. Full logout purges token, key from Keystore/Keychain, and deletes all local `.enc` files.

### NOT Verified by Automated Tests (Platform Limitations)
- **Real Face ID / Android BiometricPrompt Hardware**: Automated tests run on iOS Simulator using a controllable fake biometric service. Hardware-backed Secure Enclave / TEE authentication, actual Face ID camera capture, and OS lockout policies require physical device testing.
- **Android `FLAG_SECURE`**: Enabled in `MainActivity.kt` to blank out the app in recent task switchers and prevent screenshots, but OS window compositor behavior cannot be verified within the Flutter test process.
- **iOS App Switcher Privacy Snapshot Cover**: `SceneDelegate.swift` and `AppDelegate.swift` present a privacy overlay when resigning active, but the OS-level application switcher thumbnail capture cannot be tested through Flutter driver assertions.
- **Backup Exclusion (`NSURLIsExcludedFromBackupKey`)**: The native channel applies the backup exclusion flag to the support directory, but actual exclusion from iCloud and iTunes backups can only be verified during an OS backup cycle.
- **Real Native Apple/Google Wallet Modal Sheets**: Pass presentation sheets are displayed out-of-process by system services (`PassKit` / Google Play Services) and cannot be inspected by Flutter widget/integration tests.

---

## 12. Apple Wallet PassKit Requirements & Cryptographic Signing

- **PassKit Requirement**: Adding passes to Apple Wallet via `PassKit` (`PKPassLibrary.addPasses`) strictly requires a validly formatted `.pkpass` ZIP archive containing:
  1. `pass.json`: The pass model definition.
  2. `manifest.json`: SHA hashes of all files in the archive.
  3. `signature`: A cryptographic PKCS#7 signature produced by an Apple Pass Type ID certificate and private key.
- **Entitlements**: The iOS application must be provisioned with the `com.apple.developer.pass-type-identifiers` entitlement matching the Pass Type ID.
- **Development Backend Stubs**: The backend currently serves unsigned pass stubs indicated by the `X-Pass-Stub: true` header and lack of a `signature` archive entry.
- **Defensive Handling**: `WalletProvisioner` and `AppleWalletProvisioner` inspect incoming passes, detect unsigned stubs, and return `WalletProvisionStubError`, displaying a clear error message in the UI instead of attempting to load invalid bundles into `PassKit`.

