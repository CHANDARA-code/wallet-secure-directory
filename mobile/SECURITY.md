# Mobile Wallet Security Architecture & Limitations

## 1. Cryptographic Architecture

### Key Lifecycle and Storage
- **Algorithm**: AES-256 in Galois/Counter Mode (AES-GCM).
- **Key Generation**: 32-byte (256-bit) cryptographically secure random keys are generated on-device using Dart's CSPRNG `Random.secure()`.
- **First-Time Provisioning**: Key existence is checked via a non-secret-returning existence check (`hasKey()`). If no key exists in secure storage, a key is generated with `Random.secure()`, written to secure storage, and returned without prompting for biometrics since no existing secret is being released.
- **Biometric Key Gating**: Once an encryption key exists, subsequent retrieval from secure storage must be authorized through `BiometricKeyProvider`. In the default configuration (`OS_BOUND_KEY=false`), this enforces an application-level biometric prompt via `local_auth` (`biometricOnly: true`). When built with `--dart-define=OS_BOUND_KEY=true`, retrieval triggers OS-level biometric release in Keystore/Keychain.
- **Document Loading & Automatic Encrypted Storage**:
  - The `signIn` flow itself does not read the encryption key; it writes the session bearer token atomically to secure storage.
  - However, upon successful authentication, `loadDocuments` is triggered automatically to fetch document metadata.
  - Any issued document not yet stored locally is automatically downloaded, encrypted with AES-256-GCM, and stored in the Application Support directory (`doc_<id>.enc`) without requiring manual user intervention.
  - **Prompt Rules**: If no key exists yet, `getOrCreateEncryptionKey()` creates and stores one without prompting. If an encryption key already exists (or in OS-bound mode with an existing key, or when unstored/mismatched documents are present), exactly **one** biometric prompt covers the entire batch fetch and encryption operation.
  - **Biometric Denial**: If biometrics are cancelled or denied during auto-store, `keyResult` returns `KeyRetrievalFailure`; batch encryption is safely skipped, documents remain in memory/network state with `isStoredOffline: false`, and the application does not crash.
  - **In-Flight Load Serialization**: An internal Future guard (`_activeLoadFuture`) serializes concurrent calls to `loadDocuments`. If a load is already in progress, additional invocations await the active Future.
  - **Key & Plaintext Buffer Zeroing**: In a `finally` block enclosing the batch re-encryption/auto-store operation, active key bytes are zeroed (`key.fillRange(0, key.length, 0)`). In addition, each document's raw payload bytes (`rawBytes`) are zeroed in their own `finally` blocks immediately after encryption.
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

### Capabilities of `flutter_secure_storage` (v11.2.0) and the `OS_BOUND_KEY` Opt-In

The installed version of `flutter_secure_storage` (v11.2.0) provides fine-grained biometric access control on both iOS and Android:
- **iOS**: Configured with `accessControlFlags: [AccessControlFlag.biometryCurrentSet, AccessControlFlag.userPresence]` alongside `KeychainAccessibility.first_unlock_this_device` and `synchronizable: false`.
- **Android**: Configured with `AndroidOptions.biometric(resetOnError: true, enforceBiometrics: true, requireBiometricsPerOperation: true, biometricPromptTitle: 'Authenticate to access document key', biometricPromptSubtitle: 'Biometric authentication required', biometricPromptNegativeButton: 'Cancel')`.

#### Compile-Time Opt-In Flag
The application uses these OS-bound biometric storage options **ONLY** when compiled with the explicit flag:
```bash
--dart-define=OS_BOUND_KEY=true
```
- By default (`OS_BOUND_KEY=false`), the app uses standard secure storage without OS biometric constraints, relying on the unified `local_auth` application-level gate.
- **Hardware Status**: OS-bound key mode compiles cleanly and runs in automated test suites, but has **not yet been validated on physical hardware devices** with real Secure Enclave / Keymaster TEE chips.

#### Distinct Key Names & Migration Semantics
To prevent collisions and enable clean migration between modes, `FlutterSecureStorageService` maintains distinct key names in secure storage:
- Default / unbound key: `'doc_aes_gcm_key'`
- OS-bound key: `'doc_aes_gcm_key_os_bound'`
- Session bearer token: `'auth_bearer_token'`

**Migration Behavior**:
1. When the app boots in a mode different from when documents were previously saved, `hasMismatchedKey()` detects the key under the alternate name.
2. In `loadDocuments`, all currently stored documents are re-downloaded and re-encrypted using the active key mode.
3. Crucially, the mismatched legacy key is deleted via `clearMismatchedKey()` **only after all stored documents have been re-encrypted**. If any step fails, the legacy key is preserved to prevent unrecoverable data loss.

#### `biometryCurrentSet` Invalidation Risk & Automatic Recovery
- **The Invalidation Risk**: When iOS Keychain items are bound with `AccessControlFlag.biometryCurrentSet`, adding a new fingerprint or altering Face ID enrollment causes the OS to permanently invalidate the cryptographic item. Android Keystore similarly invalidates biometric keys when new fingerprints are enrolled.
- **Exception Mapping**: Low-level platform exceptions (such as `KeyPermanentlyInvalidatedException`, `-25293` / `errSecItemNotFound`, `biometry set changed`) are caught and mapped by `BiometricKeyProvider` to `BiometricStatus.keyInvalidated`.
- **Automatic Recovery Flow (`_recoverFromInvalidatedKey`)**:
  1. The invalidated key is purged from secure storage (`deleteKey()`).
  2. All outdated local encrypted files are purged from the filesystem (`deleteAllEncryptedDocuments()`).
  3. A fresh 256-bit AES master key is generated with `Random.secure()` and written to secure storage.
  4. Active documents are re-fetched from the backend and encrypted under the fresh key.
  5. The UI surfaces an honest notice to the user: *"Biometric settings changed: stored documents were refreshed."*

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

## 4. In-Memory Hygiene, Form Fields, & Dart String Immutability

### Plaintext Lifecycle & Disposal
- Decrypted identity document payloads are held in `DecryptedDocumentNotifier`, a Riverpod state notifier with a nullable state (`DecryptedDocument?`).
- Plaintext data is managed as `Uint8List` byte buffers.
- **Synchronous Zeroing on Dispose**: When `DocumentViewerScreen` is disposed, it calls `_viewerNotifier.clearDeferred()`. This wipes the underlying byte buffer synchronously (`current.zeroAndDispose()`, overwriting every byte of `rawBytes` with `0x00`), and defers the Riverpod state reset (`state = null`) to a `Future.microtask`. This prevents modifying provider state during the Flutter widget tree dispose pass.
- **Synchronous Lifecycle Backgrounding Lock**: When the application lifecycle transitions to `AppLifecycleState.inactive`, `paused`, or `hidden`, `clear()` is invoked synchronously. It overwrites all managed plaintext byte buffers with `0x00` and immediately resets `state = null`. When the app resumes, the screen renders the locked view requiring biometric re-authentication.

### Always-Obscured Password Fields
- In `LoginScreen` and `CreateAccountScreen`, all password fields (password and confirm-password) have `obscureText: true` hardcoded.
- There is no compile-time switch or toggle that alters or disables this behavior.
- The only `fromEnvironment` values read in `mobile/lib/` are:
  - `API_BASE_URL` (in `lib/core/network/api_client.dart`)
  - `OS_BOUND_KEY` (in `lib/core/storage/secure_storage_service.dart`)

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

## 7. Native OS Wallet Passes & Architecture

- **Architecture & Bridges**: The app interfaces with native mobile wallets through `WalletProvisioner` and `PlatformNativeWalletBridge` (`GoogleWalletProvisioner` and `AppleWalletProvisioner`):
  - On iOS, `PlatformNativeWalletBridge` invokes the `com.example.wallet_app/wallet` `MethodChannel`, handled by `WalletChannelHandler.swift` which delegates to `PKAddPassesViewController`.
  - On Android, `PlatformNativeWalletBridge` invokes the `add_to_google_wallet` plugin (`com.droidsonroids/loyalty_pass`).
  - Unsupported platforms (web, desktop) fall back to an unavailable bridge returning `WalletProvisionUnavailable`.
- **Stub Detection Defense-in-Depth**:
  - Unsigned stub passes are rejected defensively before any native platform channel or plugin call:
    - **Apple Pass**: Inspected for the `X-Pass-Stub: true` header OR decoded to verify that the `.pkpass` ZIP archive contains a valid `signature` file. If missing, `AppleWalletProvisioner` returns `WalletProvisionStubError`.
    - **Google Pass**: Inspected for the `X-Pass-Stub: true` header, `stub: true` JSON body, OR a JWT header with `alg: none`. Any of these conditions immediately returns `WalletProvisionStubError`.
  - When a stub is detected, native channels receive zero invocations, and the UI displays an informative message.
- **Confirmation Semantics & Exactly-Once Results**:
  - **iOS Confirmation**: Pass addition is queried via `PKPassLibrary().containsPass(pass)`. It returns `true` (added/confirmed) -> `WalletProvisionSuccess`, `false` (user pressed Cancel) -> `WalletProvisionCancelled`, or `unknown`/`null` -> `WalletProvisionFailure('Pass addition could not be confirmed.')`. The app never reports success without positive confirmation from `PKPassLibrary`.
  - **Android Confirmation**: Handled via `saveLoyaltyPass` completion listeners (`onSuccess` -> `WalletProvisionSuccess`, `onCanceled` -> `WalletProvisionCancelled`, `onError` -> `WalletProvisionFailure`).
  - **Cancellation & Busy**: Both `WalletProvisionCancelled` and `WalletProvisionBusy` are modeled as quiet outcomes without disruptive error SnackBars.
  - **Bridge Timeout**: All native invocations are bounded by a 5-minute timeout (`Duration(minutes: 5)`), returning `WalletProvisionFailure('Pass provisioning timed out waiting for the wallet.')`. Late callbacks from the OS are safely dropped without throwing double-completion errors.
- **Physical Device & Credential Constraints**:
  - Real signed passes and real out-of-process OS presentation sheets have **not been verified on physical hardware devices**. Real verification requires active Apple Developer Program and Google Wallet Console credentials.

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
- **Production URL**: Strict `https://` required in release mode (`kReleaseMode`).
- **Run Flags**:
  - `flutter run -d <device-id> --dart-define=API_BASE_URL=<url>`
  - `flutter run -d <device-id> --dart-define=API_BASE_URL=<url> --dart-define=OS_BOUND_KEY=true`
- **Integration Test Execution**:
  - One-command automated runner: `mobile/tool/run_integration_test.sh`
  - Manual execution: `flutter test integration_test -d <device-id> --dart-define=API_BASE_URL=http://localhost:3170 --dart-define=QA_EMAIL=<email> --dart-define=QA_PASSWORD=<password>`

---

## 11. Security Verification Matrix: Verified vs. Unverified

### 1. Verified by Automated Unit and Widget Tests
- **Crypto & Envelope v2**: AES-256-GCM encryption and decryption, unique 12-byte IV per operation, 16-byte authentication tag, AAD document ID binding (`wallet-doc:v2:$documentId`), rejection of tampered ciphertext/tag/IV, rejection of legacy v1 envelopes, and zeroing of key byte arrays in memory (`Uint8List.fillRange(0, length, 0)`).
- **Filesystem Traversal Defense**: Strict document ID regex validation (`^[A-Za-z0-9_-]{1,128}$`), blocking directory traversal attacks (`../`, `/`, `\`). Envelopes written to Application Support directory.
- **Safe Key Migration**: `hasMismatchedKey()` detects cross-mode keys; re-encrypts all stored documents before deleting the old key via `clearMismatchedKey()`.
- **Invalidated Key Recovery**: Detects key invalidation exceptions (`KeyPermanentlyInvalidatedException`, `-25293`, etc.), purges invalidated key and local files, writes fresh key, re-downloads issued documents, and surfaces user notice.
- **In-Flight Load Serialization**: Concurrent `loadDocuments` calls reuse the active Future.
- **Native Wallet Bridge Logic**: Stub rejection (Apple ZIP missing signature / `X-Pass-Stub`; Google `alg: none` / `X-Pass-Stub`), platform channel result mapping (`true` -> Success, `false` -> Cancelled, `busy` -> Busy, timeout -> Failure), 5-minute timeout with late callback immunity, UI debounce (two rapid taps invoke provision once).
- **Obscured Form Fields**: Unit/widget tests assert `obscureText: true` on login and registration password fields with zero disabling switches.
- **In-Memory Hygiene & Lifecycle Wipe**: `DecryptedDocumentNotifier` zeroes byte buffers synchronously and defers state reset on widget disposal; resets state and zeroes buffers immediately on lifecycle `inactive`, `paused`, or `hidden`.
- **Authentication & Atomic Storage**: Token and key generation on sign-in/sign-up are atomic; failure deletes the token. Full logout purges token, key from Keystore/Keychain, and deletes all local `.enc` files.

### 2. Verified on iOS Simulator by Integration Test
The end-to-end integration test (`mobile/integration_test/e2e_faked_biometrics_simulator_test.dart`) has completed real automated runs on an iOS 18.3 simulator against a private backend instance. It asserts:
1. **Live Authentication**: Signs in with QA credentials against the live backend (`POST /api/auth/sign-in/email`).
2. **Automatic Encrypted Storage**: Newly fetched document is automatically encrypted with AES-256-GCM and saved to Application Support as `.enc` envelope v2 (`0x02`); on-disk bytes are verified to contain zero occurrences of the plaintext holder name (`QA User`).
3. **Biometric Gate Rejection**: When controllable biometrics return false, tapping "View Document" keeps the viewer unopened, leaves the decrypted notifier null, and displays no plaintext.
4. **Offline Viewing Without Network Calls**: With network traffic disabled via `ToggleableHttpClient` throwing socket exceptions, granting biometrics decrypts the document, renders decrypted claims ('Full Name', 'QA User'), updates the notifier, and verifies 0 HTTP requests.
5. **Route Pop Zeroing**: Returning from `DocumentViewerScreen` via the back button resets the decrypted document notifier to null.
6. **Lifecycle Inactivity Wipe**: Reopening the document and dispatching `AppLifecycleState.paused` immediately clears decrypted document buffers in memory; resuming displays the "Document Locked" view.
7. **Biometric Re-Unlock While Offline**: Re-unlocking while offline verifies rejection maintains the lock, while grant decrypts and displays fields with 0 network calls.
8. **Session Purge on Sign Out**: Tapping Sign Out purges the bearer token and master encryption key from secure storage, and deletes all `.enc` files from disk.
9. **User Registration**: Navigates to Create Account, registers a new user with a unique timestamped email, verifies immediate sign-in, token persistence, and key creation, followed by clean sign-out.

### 3. Compiled but NOT Run on Physical Devices
- `PlatformNativeWalletBridge` and `WalletChannelHandler.swift` compile for iOS Simulator.
- Android debug build compiles with `com.google.android.gms.wallet.api.enabled` in `AndroidManifest.xml`.
- `OS_BOUND_KEY=true` compile-time mode with `AccessControlFlag.biometryCurrentSet` / `userPresence` on iOS and `AndroidOptions.biometric` on Android compiles cleanly in test harnesses, but has not been run or validated on physical device hardware.

### 4. NOT Verified (Platform Limitations)
- **Real Face ID / Android BiometricPrompt Hardware**: Automated tests run on iOS Simulator using a controllable fake biometric service. Hardware-backed Secure Enclave / Keymaster TEE authentication, actual Face ID camera capture, and OS biometric lockout policies require physical device testing.
- **Android `FLAG_SECURE`**: Enabled in `MainActivity.kt` to blank out the app in recent task switchers and prevent screenshots, but OS window compositor behavior cannot be verified within the Flutter test process.
- **iOS App Switcher Privacy Snapshot Cover**: `SceneDelegate.swift` and `AppDelegate.swift` present a privacy overlay when resigning active, but OS application switcher thumbnail capture cannot be tested through Flutter driver assertions.
- **Backup Exclusion (`NSURLIsExcludedFromBackupKey`)**: Native channel applies the backup exclusion flag to the support directory, but actual exclusion from iCloud and iTunes backups can only be verified during an OS backup cycle.
- **Real Native Apple/Google Wallet Modal Sheets**: Out-of-process system sheets cannot be automated in test harnesses. Real signed passes require production Apple/Google signing credentials.

---

## 12. Apple Wallet PassKit Requirements & Cryptographic Signing

- **PassKit Requirement**: Adding passes to Apple Wallet via `PassKit` (`PKPassLibrary.addPasses`) strictly requires a validly formatted `.pkpass` ZIP archive containing:
  1. `pass.json`: The pass model definition.
  2. `manifest.json`: SHA hashes of all files in the archive.
  3. `signature`: A cryptographic PKCS#7 signature produced by an Apple Pass Type ID certificate and private key.
- **Signed Mode vs. Stub Mode**:
  - **Signed Pass Mode**: When server credentials (`APPLE_PASS_TYPE_ID`, `APPLE_TEAM_ID`, `APPLE_PASS_CERT_PATH`, `APPLE_PASS_KEY_PATH`, `APPLE_WWDR_CERT_PATH`) are configured in `backend/.env`, the backend generates cryptographically signed `.pkpass` bundles (`X-Pass-Stub: false`) with detached PKCS#7 signatures created via `pkijs` and `asn1js`. Pass content is minimal (holder name, document number, license classes, expiry date).
  - **Development Stubs**: When credentials are not configured, the backend serves unsigned pass stubs indicated by the `X-Pass-Stub: true` header and lack of a `signature` archive entry.
- **Defensive Handling**: `WalletProvisioner` and `AppleWalletProvisioner` inspect incoming passes, detect unsigned stubs, and return `WalletProvisionStubError`, displaying a clear error message in the UI instead of attempting to load invalid bundles into `PassKit`.

