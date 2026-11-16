# Changes: stable Device ID, offline mode, optional Device ID update

## 1. Device ID: same on a phone for debug, release and Play builds
- Android ID depends on the signing key, so it can NOT be the same across debug/release/Play. It was replaced by a hashed Widevine
  device id (`MainActivity.kt`, channel `com.sales.ba/device`), which belongs to the phone and does not depend on the signing key.
- Saved locally after the first read (`device_id_v2`). Phones without Widevine fall back to Android ID.
- Old ids in the database (e.g. 4003dabd04d938c5) are Android IDs and will not match: one-time re-registration via "Update Device ID",
  or update the stored ids on the server.
- Changes only on factory reset.
- Test: install debug + release on the same phone; the Device ID chip on the login screen must show the same value.

## 2. Offline mode message
- `ApiException` now has `isNetwork` / `isTimeout`; any "no response" shows: "You're in offline mode. No internet connection."
- A bar on top of every screen shows the same message while offline (`Widgets/offline_banner.dart`, `Data/network_status.dart`).
- While offline the server host is checked every 8 s; when it answers the bar disappears and queued items sync automatically.
- Timeouts show the offline message but are NOT queued (the server may already have received the request).

## 3. Offline images
- Shelf pictures are saved as files in app-private storage (per BA, newest 150 kept) and the list is saved too (`Data/shelf_cache.dart`).
- Newest 30 pictures are downloaded in the background after the list loads.
- Offline: list + saved pictures open normally; unsaved ones show "Offline - tap to retry".
- Pictures taken offline appear at the top as "Saved offline - waiting to upload".

## 4. Update Device ID is shown only when needed
- At app start the login screen calls `POST /auth/device-id/check/` with `{ "device_id": ... }`.
- The button appears only if `show_update_option` is true (falls back to `registered == false` if the field is missing).
- Registered device => no button. If the check fails (offline) the button stays hidden and is re-checked when internet returns.
- Not shown on the Profile screen (a logged-in BA's device is already registered).

## Files
New: `Data/network_status.dart`, `Data/shelf_cache.dart`, `Widgets/offline_banner.dart`
Changed: `Repository/repository.dart`, `main.dart`, `MainActivity.kt`, `Data/device_id.dart`, `Screens/app_shell.dart`,
`Screens/auth_screen.dart`, `Screens/profile_screen.dart`, `Screens/device_update_sheet.dart`,
`Screens/shelf_images_screen.dart`, `Model/shelf_models.dart`, `pubspec.yaml` (path_provider)
Not compiled here (no Flutter SDK): run `flutter pub get && flutter analyze` first.
