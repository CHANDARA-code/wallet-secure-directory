# API Contract (v1)

Single source of truth shared by `backend/`, `mobile/` and `admin/`. If an implementation needs to deviate, change this file in the same change and say so in the delivery report.

Base URL (dev): `http://localhost:3000`. All routes are prefixed `/api`. Errors use Nest's default shape: `{ "statusCode": number, "message": string | string[], "error": string }`.

## Authentication (already implemented, better-auth)

| Method | Path | Notes |
| --- | --- | --- |
| POST | `/api/auth/sign-up/email` | body `{ name, email, password }` |
| POST | `/api/auth/sign-in/email` | body `{ email, password }` -> `200 { token, user }`; also sets header `set-auth-token` and a session cookie |
| GET | `/api/auth/get-session` | `{ session, user }` or `null` |
| POST | `/api/auth/sign-out` | body `{}` |

- Mobile: read the `set-auth-token` response header, store it in the platform keystore, send `Authorization: Bearer <value>` on every later request.
- Web admin: cookie session. Run the Vite dev server with a proxy for `/api` to `http://localhost:3000` so requests are same-origin; send `credentials: "include"`.
- User object: `{ id, name, email, emailVerified, image, role: "user" | "admin", createdAt, updatedAt }`.

## Identity document model

`type` is `"driving_license"` (only value for now). `status` is `"issued" | "revoked"`.

`data` for `driving_license`:

```json
{
  "fullName": "Sok Dara",
  "dateOfBirth": "1995-04-12",
  "address": "12 Street 51, Phnom Penh",
  "nationality": "KH",
  "issuingAuthority": "Ministry of Public Works and Transport",
  "licenseClasses": ["B", "C1"],
  "restrictions": ["CORRECTIVE_LENSES"],
  "issueDate": "2026-01-15",
  "expiryDate": "2036-01-14"
}
```

Dates are `YYYY-MM-DD`. `licenseClasses` has at least one entry; `restrictions` may be empty. The server generates `documentNumber` (format `DL-` followed by 10 digits, unique) and sets `expiresAt` to the end of `expiryDate` in UTC.

## User endpoints (any authenticated user, bearer or cookie)

All document responses carry `Cache-Control: no-store`. A document that does not exist, belongs to another user, or is revoked returns `404` (never `403`) so existence is not leaked. No session returns `401`.

### `GET /api/documents`
Own non-revoked documents, newest first.
```json
[{ "id": "...", "type": "driving_license", "documentNumber": "DL-0123456789", "status": "issued", "issuedAt": "2026-01-15T00:00:00.000Z", "expiresAt": "2036-01-14T23:59:59.999Z" }]
```

### `GET /api/documents/:id`
The raw document JSON the mobile app encrypts and stores.
```json
{ "id": "...", "type": "driving_license", "documentNumber": "DL-0123456789", "issuedAt": "...", "expiresAt": "...", "data": { } }
```

### `GET /api/documents/:id/pass/apple`
`200`, `Content-Type: application/vnd.apple.pkpass`, `Content-Disposition: attachment; filename="<documentNumber>.pkpass"`, `Cache-Control: no-store`.

- **Signed mode** (when Apple credentials `APPLE_PASS_TYPE_ID`, `APPLE_TEAM_ID`, `APPLE_PASS_CERT_PATH`, `APPLE_PASS_KEY_PATH`, `APPLE_WWDR_CERT_PATH` are configured):
  Response header `X-Pass-Stub: false`. Package contains `pass.json`, `manifest.json`, `icon.png`, `icon@2x.png`, and a DER detached PKCS#7 `signature` over `manifest.json` signed with the signer certificate/key and WWDR chain. Visible fields are minimal (holder name, document number, license classes, expiry date; no date of birth or address).
- **Stub mode** (fallback when credentials are not configured):
  Response header `X-Pass-Stub: true`. An unsigned zip containing `pass.json` and `manifest.json`.

### `GET /api/documents/:id/pass/google`
`200`, `Content-Type: application/json`, `Cache-Control: no-store`.

- **Signed mode** (when Google Wallet credentials `GOOGLE_WALLET_ISSUER_ID`, `GOOGLE_WALLET_SERVICE_ACCOUNT_EMAIL`, `GOOGLE_WALLET_PRIVATE_KEY_PATH` are configured):
  `200 { "jwt": "<RS256 JWT signed with service account private key>", "saveUrl": "https://pay.google.com/gp/v/save/<jwt>", "stub": false }`. Claims include `iss`, `aud: "google"`, `typ: "savetowallet"`, `iat`, `origins`, and `payload.genericObjects` with minimal visible fields (no date of birth or address).
- **Stub mode** (fallback when credentials are not configured):
  `200 { "jwt": "<unsigned dev JWT with alg: none>", "saveUrl": "https://pay.google.com/gp/v/save/<jwt>", "stub": true }`.

Stubs must never claim to be signed by Apple or Google (`stub: true` / `X-Pass-Stub: true`). Real signing activates only when complete provider credentials are configured in the backend environment.

## Admin endpoints (session user must have `role: "admin"`, otherwise `403`; no session `401`)

Pagination: `limit` (1-100, default 20) and `offset` (default 0). Responses are `{ "items": [...], "total": number }`.

### `GET /api/admin/users?limit&offset&q=`
`q` matches name or email, case-insensitive.
```json
{ "items": [{ "id": "...", "name": "...", "email": "...", "role": "user", "createdAt": "...", "documentCount": 1 }], "total": 1 }
```
`documentCount` counts non-revoked documents.

### `GET /api/admin/documents?limit&offset&userId=`
```json
{ "items": [{ "id": "...", "userId": "...", "userEmail": "...", "type": "driving_license", "documentNumber": "DL-...", "status": "issued", "issuedAt": "...", "expiresAt": "...", "revokedAt": null }], "total": 1 }
```

### `POST /api/admin/documents`
Body `{ "userId": "...", "type": "driving_license", "data": { ... } }`. Validates `data` strictly (unknown keys rejected). `201` with one item in the shape above. Unknown `userId` returns `404`; invalid body returns `400` with field messages.

### `POST /api/admin/documents/:id/revoke`
`200` with the updated item (`status: "revoked"`, `revokedAt` set). Revoking twice is idempotent. Unknown id returns `404`.

## Bootstrapping an admin

`npm run seed:admin` in `backend/` reads `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `ADMIN_NAME` from the environment, creates the user through better-auth if missing, then sets `role = "admin"`. Safe to run repeatedly.
