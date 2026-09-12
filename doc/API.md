# Attendance API — Mobile Client Reference

Base URL: `https://<host>/api` (host/port depend on deployment — see `server.mjs` for the current dev server, LAN IP + port 8080 over HTTPS with a self-signed cert).

This document describes the API **as currently implemented**, including a
few rough edges and one recent breaking change (admin-gated endpoints).
Where behavior is inconsistent or incomplete, it's called out explicitly —
don't assume undocumented consistency.

## Auth model

There is no session cookie or per-request token for regular officers today.
Endpoints like clock-in/clock-out/verify identify the officer purely by the
`officer_id` (or `id`) value the client sends in the request — there is no
server-side proof that the caller *is* that officer. Treat this as a known
gap, not a design to build further trust on top of.

**Admin actions are different.** A small set of endpoints (officer
create/update/delete, password reset) require an admin bearer token:

1. An officer with `role: "admin"` logs in via `POST /api/auth/login`.
2. The login response includes an extra `admin_token` field (regular
   officers never see this field).
3. Send it on admin-gated requests: `Authorization: Bearer <admin_token>`.
4. Tokens expire after 12 hours; re-login to get a new one.

If you don't have an admin login (this is a back-office capability, not
something the officer-facing app should need), you don't need to worry
about the `Authorization` header at all — just skip those endpoints.

## Response shapes (not fully consistent — check each endpoint)

Two different envelope styles are used across the API:
- `{ code: "000", message, data }` on success, `{ message }` on error
- `{ success: true, ... }` on success, `{ success: false, message }` on error

Both use conventional HTTP status codes for errors (400/401/403/404/500).
Don't assume one global shape — each endpoint below shows its actual
response.

---

## Auth

### `POST /api/auth/register`
No auth required.

**Body (JSON)**
```json
{ "officer_id": "OFF123", "email": "a@b.com", "password": "secret123", "name": "Jane Doe", "department": "IT", "position": "Analyst", "phone_number": "0244..." }
```
`email` and `password` are required; everything else optional.

**Success (200)**
```json
{ "code": "000", "message": "Registration successful", "data": { "name": "Jane Doe", "email": "a@b.com", "department": "IT", "officer_id": "OFF123" } }
```

⚠️ **New accounts are created inactive (`is_active: false`)** and cannot log
in until an admin approves them (`PATCH /api/officers` with
`is_active: true`). Build the registration flow to tell the user their
account is pending approval — don't expect an immediate working login.

**Errors**: `400` missing email/password · `409` already registered · `500`

---

### `POST /api/auth/login`
No auth required.

**Body**
```json
{ "officer_id": "OFF123", "password": "secret123" }
```

**Success (200)**
```json
{
  "code": "000",
  "message": "Login successful",
  "data": {
    "name": "Jane Doe",
    "username": "OFF123",
    "email": "a@b.com",
    "department": "IT",
    "officer_id": "OFF123",
    "directory": { "...": "full officer record from the database" }
  }
}
```
If the officer's `role` is `"admin"`, `data.admin_token` is also present —
see [Auth model](#auth-model).

**Errors**
- `400` missing officer_id/password
- `404` officer not found
- `401` `"Password reset required — contact an administrator"` (account has
  no password set — ask an admin to reset it) or `"Invalid officer ID or
  password"` (wrong password)
- `403` `"Account pending approval"` (registered but not yet approved)
- `500`

---

### `POST /api/auth/logout`
No auth required, no body. Clears server-set session cookies. These cookies
are a leftover from a web-dashboard flow and aren't set by anything else in
this API (login doesn't set them) — the mobile app doesn't need to send
cookies and can just discard whatever it's storing locally on logout.

**Response**: `{ "success": true }`

---

### `POST /api/auth/forgot-password` — 🔒 admin only
**Not self-service.** Requires `Authorization: Bearer <admin_token>`. Do not
build a "forgot password" UI in the mobile app that hits this directly —
there's no verification step an ordinary officer can complete. If you need
self-service reset, that's a separate feature to request (e.g. email/SMS
OTP), not something this endpoint currently supports.

**Body**
```json
{ "officer_id": "OFF123", "new_password": "newSecret123" }
```
`new_password` must be at least 6 characters.

**Success (200)**
```json
{ "code": "000", "message": "Password reset successfully", "officer_id": "OFF123" }
```

**Errors**: `401` missing/invalid admin token · `403` not an admin, or
account inactive · `400` validation · `404` officer not found · `500`

---

## Officers

### `GET /api/officers`
No auth required. Optional `?officer_id=OFF123` to filter to one officer;
omit it to list all officers.

**Response**: `{ "code": "000", "data": [ { ...officer }, ... ] }`

### `GET /api/officers/{id}`
No auth required. `{id}` is the officer's internal `id` (primary key), not
`officer_id`.

**Response**: `{ "code": "000", "data": { ...officer } }` · `404` if not found

### `POST /api/officers` — 🔒 admin only
Create an officer directly (distinct from self-registration).

**Body**: `officer_id`, `full_name`, `email` required; `is_active`,
`department`, `position`, `phone_number` optional.

### `PATCH /api/officers` — 🔒 admin only
Partial update, matched by `officer_id` in the body. This is also how you
**approve a pending registration**: `{ "officer_id": "OFF123", "is_active": true }`.
Also accepts `password` (plaintext — server hashes it).

### `PUT /api/officers` — 🔒 admin only
Full replace, matched by `officer_id` in the body (`officer_id`,
`full_name`, `email` required).

### `DELETE /api/officers?officer_id=OFF123` — 🔒 admin only

### `PATCH /api/officers/{id}` / `PUT /api/officers/{id}` / `DELETE /api/officers/{id}` — 🔒 admin only
Same semantics as the collection-level routes above, but targeting the
officer's internal `id` instead of matching by `officer_id` in the body.

---

### `POST /api/officers/register-face`
No auth required — called by the mobile app during officer onboarding.

**Body**: `multipart/form-data` with `image` (file) and `officer_id` (text).

**Success (200)**
```json
{
  "success": true,
  "message": "Face registered successfully.",
  "officer": { "officer_id": "OFF123", "full_name": "Jane Doe", "email": "a@b.com" },
  "face": { "face_token": "...", "confidence": 97.2, "rectangle": { "...": "..." } },
  "imageUrl": "https://.../face-images/..."
}
```

**Errors**: `400` no image / no officer_id / no face detected · `500` upload
or Face++ failure

### `GET /api/officers/register-face?officer_id=OFF123`
Check whether an officer already has a face registered.

**Response**: `{ "has_face": true, "officer": {...}, "face": { face_token, confidence, image_path, imageUrl } }`
or `{ "has_face": false, "officer": {...}, "message": "..." }` · `404` if officer not found

---

## Attendance

### `POST /api/attendance/clock-in`
No auth required.

**Body**: `{ "id": "OFF123", "comment": "optional note" }`

**Response**: `{ "code": "000", "message": "Clock in successful", "data": { ...record } }`

### `POST /api/attendance/clock-out`
Same shape as clock-in. Looks up today's open (not-yet-clocked-out) record
for the officer and closes it. Returns `400` `"No open attendance found.
Please clock in first."` if there isn't one.

### `POST /api/attendance/check` — face-based clock in/out
No auth required.

**Body**: `multipart/form-data` with `image` (file), `action`
(`"clock_in"` or `"clock_out"`), optional `location`.

Matches the face against the Face++ faceset, resolves it to an officer,
then performs the same clock-in/out logic as above.

**Response** (varies by outcome — check `success`/`hasFace`):
```json
{
  "success": true,
  "hasFace": true,
  "officer": { "officer_id": "OFF123", "full_name": "Jane Doe", "email": "a@b.com", "department": "IT" },
  "message": "Clocked in successfully.",
  "attendance": { "...": "..." },
  "imageUrl": "https://...",
  "confidence": 91.4
}
```
No face match → `{ "success": false, "hasFace": false, "message": "No matching face found or confidence too low.", "confidence": 0 }`

### `GET /api/attendance/history?id=OFF123`
Returns the officer's most recent daily **summary** row (one record: today
or the latest date with data) — not full history.

**Response**: `{ "code": "000", "data": { ...summary } }` · `404` if none

### `/api/attendance/history/{id}` — full CRUD, not just history
⚠️ Despite the path, this is generic CRUD on individual attendance rows.
The `{id}` path segment is **only used by GET**; the other methods take
their own IDs in the body/query.

- `GET /api/attendance/history/{id}` — `{id}` = `officer_id`. Returns the
  officer's full raw attendance list (all clock-in/out rows), newest
  first. `{ "code": "000", "data": [ {...}, ... ] }`
- `POST /api/attendance/history/{id}` — `{id}` in the URL is **ignored**;
  body must include `officer_id`. Creates a raw attendance row.
- `PATCH /api/attendance/history/{id}` — `{id}` in the URL is **ignored**;
  body must include `attendance_id`. Sets `clock_out`.
- `DELETE /api/attendance/history/{id}` — `{id}` in the URL is **ignored**;
  use `?id=<attendance_id>` query param instead.

### `GET /api/attendance/all-attendance/{id}?id=OFF123`
⚠️ Another path/query mismatch: the `{id}` path segment is ignored — pass
the officer ID as `?id=` query param instead. Returns the same "latest
summary row" shape as `/api/attendance/history`.

---

## User / branch data

These three endpoints currently return **static, hardcoded data** — not
looked up per-user. Treat them as placeholders.

### `POST /api/user/location`
No body needed. **Response**: `{ "success": true, "data": { "latitude": 5.554944, "longitude": -0.201333 } }`

### `GET /api/user/all-locations`
**Response**: `{ "success": true, "data": [ { "id": 20, "name": "HEAD OFFICE", "lat": 5.554944, "lng": -0.201333 }, ... ] }`

### `GET /api/user/allowed-distance`
**Response**: `{ "success": true, "allowedDistance": 10000 }` (meters, presumably a geofence radius)

---

## Verify

### `POST /api/verify`
No auth required. Compares a captured face against a stored reference
image.

⚠️ This looks up an `images` table (by row `id`) and a `user-images`
storage bucket — a separate identity system from `officers`/`attendance`.
It's not covered by the schema in `supabase.sql`. Confirm with the backend
before building against this if you're expecting it to relate to
officer_id.

**Body**: `{ "id": "<images row id>", "imageBase64": "data:image/jpeg;base64,..." }`

**Response**: `{ "success": true, "confidence": 92.3, "is_match": true, "id": "...", "face_box": { "...": "..." } }`

**Errors**: `400` missing fields / no face detected · `404` user not found · `500`

---

## Upload

### `POST /api/upload`
No auth required. Generic file upload to Supabase Storage.

**Body**: `multipart/form-data` with `file` and optional `folder`.

Allowed types: `image/jpeg`, `image/png`, `image/webp`, `application/pdf`.
Max size: 10MB.

**Response**: `{ "code": "000", "message": "File uploaded successfully", "path": "...", "url": "https://..." }`

**Errors**: `400` no file / unsupported type / too large · `500`

---

## Notifications

### `POST /api/notification/send-email`
**Body**: `{ "to": "a@b.com", "subject": "optional", "message": "..." }`

**Response**: `{ "ok": true }` · `400` missing `to`/`message` · `500`

⚠️ Requires `MAIL_USER`/`MAIL_PASS` to be configured on the server — not
currently set. Confirm with backend this is live before relying on it.

### `POST /api/notification/send-sms`
⚠️ **Currently non-functional — do not integrate.** The route doesn't read
anything from the request body; phone number, message, and username are
hardcoded to empty strings in the implementation, so every call sends a
blank SMS via the internal gateway (or fails). This needs a backend fix
before it's usable.

---

## Known limitations (as of this doc)

- **No per-officer authentication on attendance endpoints.** Anyone who
  knows or guesses an `officer_id` can clock that officer in/out, or read
  their history — there's no token proving the caller is that officer.
  Flag to backend if this needs to change; it will require a client
  update (a token issued at login, sent on each request).
- `send-sms` is non-functional (see above).
- `send-email` needs mail credentials configured server-side.
- `/api/verify` targets a separate, undocumented `images` table.
- `user/location`, `user/all-locations`, `user/allowed-distance` are
  static placeholders, not real per-user/per-branch data yet.
- `attendance/history/{id}` and `attendance/all-attendance/{id}` have
  path/query inconsistencies — see the callouts above.
