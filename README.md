# GIS_Attendance — Update Channel 📲

![version](https://img.shields.io/badge/latest-v1.0.4-green?style=flat-square)
![platform](https://img.shields.io/badge/platform-Android-brightgreen?style=flat-square)
![flutter](https://img.shields.io/badge/built_with-Flutter-02569B?style=flat-square&logo=flutter)
![distribution](https://img.shields.io/badge/distribution-Self_Update-orange?style=flat-square)
![status](https://img.shields.io/badge/status-Active-success?style=flat-square)

Official over-the-air update channel for **GIS_Attendance** — the Ghana
Immigration Service staff attendance app (biometric + face-verification
clock-in/out). The installed app polls this repo and installs new builds
**in place**: no links to share, no uninstall/reinstall, no data loss.

## How it works

1. The app reads `updates/version.json` on every launch (and on demand via
   **Settings → App updates → Check for updates**).
2. If `version` is newer than the installed build, the user is offered
   **Download & Install** (or **Later** — skipped versions are remembered).
3. The APK downloads with a progress bar, then the Android installer opens
   and updates the app, keeping all logins and data.
4. `mandatory: true` forces the update (no Later button) — use for critical
   or security fixes.

## Repository structure

```text
updates/
  version.json      # polled by the app — single source of truth for updates
```

Release APKs live under **GitHub Releases** (`vX.Y.Z` tags with
`app-release.apk` attached).

## `version.json` schema

```json
{
  "version": "1.0.3",
  "apk_url": "https://github.com/Revominds/GIS_Attendance_Flutter_APP/releases/download/v1.0.3/app-release.apk",
  "mandatory": false,
  "notes": "Short human-readable changelog shown in the update dialog."
}
```

| Field       | Required | Description                                                        |
| ----------- | -------- | ------------------------------------------------------------------ |
| `version`   | ✅        | Dotted version, must be higher than the installed build to trigger |
| `apk_url`   | ✅        | Direct-download URL of the release APK                             |
| `mandatory` | ❌        | `true` blocks Later; defaults to `false`                           |
| `notes`     | ❌        | Changelog shown to officers in the update prompt                    |

## Publishing a release (maintainers)

1. Bump `version:` in the app's `pubspec.yaml` (e.g. `1.0.3`).
2. `flutter build apk --release`
3. Create GitHub Release tag `v1.0.3`, attach `app-release.apk`.
4. Update `updates/version.json` (`version` + `apk_url` + `notes`).
5. Add a `Changelog` entry below — newest version on top.
6. Devices pick it up on next launch — done. 🎉

> ⚠️ Keep the same `applicationId` and signing keys across releases,
> otherwise Android treats the build as a different app and updates will fail.

## Requirements

- Android 8.0 (API 26)+
- Internet access on first check (ML Kit model + update poll)
- "Install unknown apps" allowed for GIS_Attendance (one-time system prompt)

## Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Newest release on top.

### [1.0.4] — 2026-10-08

#### Fixed
- Face-scan `InputImageConverterError` NPE: frames are now validated (exact NV21 size, even dimensions) before reaching MLKit — malformed frames are skipped with an on-screen reason instead of crashing.
- Manual capture (📷 button) now works even when live face detection finds nothing; the server still does the real 1:1 check.
- Settings → App updates card: "Check for updates" moved to its own row (no more cramped single row).

### [1.0.3] — 2026-10-07

#### Changed
- Biometric check reverted to previous stable implementation (`local_auth` 2.x).

### [1.0.2] — 2026-10-07

#### Added
- In-app self-updater: silent check on launch + **Settings → App updates → Check for updates**.
- Update prompt with release notes, download progress bar, and Later/mandatory flows.
- `APP_UPDATE_URL` configuration (`.env`) pointing at this repo's `updates/version.json`.

#### Fixed
- Face-scan frame conversion crash (`RangeError: Only valid value is 0: 1`) on single-plane camera frames.
- Face capture now stops the preview stream before `takePicture()` (CameraX crash on some devices).

### [1.0.1] — 2026-10-06

#### Changed
- App display name: `gis_attendance` → **GIS_Attendance** (launcher + web).
- New launcher icon from `ghana_immigration_attendance_logo.png` (all densities + web).

#### Added
- `flutter_launcher_icons` setup — future logo swaps need only a re-run, no manual resizing.

### [1.0.0] — Initial release

#### Added
- Officer sign-in (password, biometric, face verification) with OTP two-factor option.
- Clock in/out with geo-fence branch check and attendance history.
- ML Kit face detection + server 1:1 face match; duty-roster PDF preview/share.

## Suggested repo topics

`flutter` · `android` · `self-update` · `ota-updates` · `gis` ·
`attendance` · `biometric` · `face-recognition` · `ghana` ·
`immigration-service` · `enterprise`

## Support

Internal distribution — Ghana Immigration Service ICT / app maintainers.
Officers: use **Settings → App updates** in the app, or contact your
branch administrator.

## License

Internal use only. All rights reserved — Ghana Immigration Service.
