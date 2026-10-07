# GIS_Attendance 📲

![version](https://img.shields.io/badge/version-1.0.2-green?style=flat-square)
![flutter](https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&logo=flutter)
![platform](https://img.shields.io/badge/platform-Android-brightgreen?style=flat-square)
![status](https://img.shields.io/badge/status-Active-success?style=flat-square)

Ghana Immigration Service staff attendance mobile app: biometric and
face-verification clock-in/out with geo-fence branch checks, attendance
history, duty rosters, and built-in self-updates (no reinstall needed).

## Features

- Officer sign-in: password, device biometrics, face verification, optional email OTP
- Clock in/out guarded by registered-branch geo-fence + location name resolution
- Face check: on-device ML Kit detection + server 1:1 face match
- Attendance history, admin dashboard, duty-roster PDF preview/share
- Push + in-app notifications; inactivity auto sign-out
- Self-updating: silent update check on launch + **Settings → App updates**

## Getting started

```bash
flutter pub get
flutter run
```

Requirements: Flutter 3.47+, Android SDK (API 26+), a device with
biometrics enrolled for biometric flows. Backend base URL comes from
`.env` (`API_BASE_URL`); update channel from `APP_UPDATE_URL`.

## Sharing / installing a build

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Upload the APK to a GitHub Release and point `updates/version.json` at it
(see the updates repo README). Phones update in place from
**Settings → App updates** — data is kept, no uninstall needed.

Rules for updatable releases:

- Bump `version:` in `pubspec.yaml` every release
- Never change `applicationId` (`com.example.gis_attendance`) or signing keys

## Project structure

```text
lib/
  config/      # AppConfig — API base URL + update URL (.env driven)
  screens/     # login, home, face verification, settings, admin …
  services/    # auth, attendance, update_service (self-updater), …
  widgets/     # app_update dialog, inactivity detector, …
android/       # launcher icon, permissions, biometric-ready MainActivity
assets/        # GIS logo, login/register art, default avatar
updates/
  version.json # mirrored to the updates repo — polled by the app
```

## Key configs

| File | Purpose |
| ---- | ------- |
| `.env` | `API_BASE_URL`, `APP_UPDATE_URL` (bundled into the APK) |
| `pubspec.yaml` | `version:` drives update ordering; `flutter_launcher_icons` regenerates icons via `dart run flutter_launcher_icons` |
| `android/app/src/main/AndroidManifest.xml` | display name `GIS_Attendance`, camera/location/biometric/install permissions |

## Changelog

### [1.0.6] — 2026-10-08
- Light + premium Dark themes with Settings → Appearance toggle (Light/Dark/System, persisted)

### [1.0.5] — 2026-10-08
- Face check rebuilt photo-based (no frame stream): auto-capture + tap 📷, on-device face presence check, then server 1:1 match
- Admin Geo-fence tab: capture precise worksite GPS + range (50–1000 m); check-in gated on precise fixes only (±100 m or better)
- App now closes on logout / sign out (manual + inactivity)

### [1.0.4] — 2026-10-08
- Fixed face-scan `InputImageConverterError` NPE (frames validated before MLKit)
- Manual capture works even when live detection finds nothing
- Settings → App updates card layout (button on its own row)

### [1.0.3] — 2026-10-07
- Biometric check reverted to previous stable implementation

### [1.0.2] — 2026-10-07
- Added in-app self-updater (launch check + Settings card, progress + mandatory flows)
- Fixed face-scan `RangeError` on single-plane frames; capture stops stream first

### [1.0.1] — 2026-10-06
- Display name `gis_attendance` → **GIS_Attendance**; new GIS launcher icon

### [1.0.0]
- Initial release: sign-in, geo-fenced clock in/out, face verification, rosters

## Support

Internal distribution — Ghana Immigration Service ICT / app maintainers.

## License

Internal use only. All rights reserved — Ghana Immigration Service.
