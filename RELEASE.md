# BA Sales - Play Store release guide (package: com.sales.ba)

## Fast path (3 things, then one command)
1. `mkdir -p ~/keystores && mv ~/Downloads/my-release-key.jks ~/keystores/` (and back it up).
2. `android/key.properties` is already filled in (alias `my-alias`).
3. Edit `android/local.properties`: set `MAPS_API_KEY=AIza...` (new, restricted key; see step 3 below).
4. `./release.sh` - verifies the keystore fingerprint, analyzes, tests, builds the signed AAB + APK and
   confirms the AAB is signed with the upload key.

## One-time setup (Mac)
1. Move the keystore out of Downloads and back it up (cloud + USB):
   `mkdir -p ~/keystores && mv ~/Downloads/my-release-key.jks ~/keystores/`
2. `cp android/key.properties.example android/key.properties` and put the real keystore password in it
   (alias is `my-alias`; PKCS12 keystore => keyPassword = storePassword).
3. Create a NEW Google Maps key, then add to `android/local.properties`:
   `MAPS_API_KEY=your_new_key`
   Restrict it (Google Cloud > Credentials) to Android apps: package `com.sales.ba` with SHA-1
   `78:0F:E0:5B:C4:75:E5:59:F2:FF:E7:E8:CA:F7:2C:BF:D1:F1:83:15` (upload key) AND the
   "App signing key" SHA-1 shown in Play Console > Setup > App signing after your first upload.
   Revoke the old key `AIzaSyD64T...` - it is in git history.
4. Clean the git repo: `git rm -r --cached build package-lock.json` then commit (build/ was tracked).

## Build
```
flutter clean && flutter pub get
dart run flutter_launcher_icons
flutter analyze && flutter test
flutter build appbundle --release
```
Upload `build/app/outputs/bundle/release/app-release.aab`. The release build stops with an error if
MAPS_API_KEY is missing. Bump `version:` in pubspec.yaml for every new upload (build number after `+` must increase).

## Test before upload
`flutter build apk --release`, install on a real phone: login, GPS/attendance, camera, maps, sales,
low stock, complaints, leave. (Code shrinking is on; test everything once.)

## Play Console checklist
- Privacy policy URL (required: precise location, photos, device ID, account data).
- Data safety form, content rating, target audience, ads = No.
- App access: provide a working test login for reviewers.
- Store listing: 512x512 icon, 1024x500 feature graphic, 2+ phone screenshots, descriptions.
- New personal developer accounts: closed test with 12+ testers for 14 days before production.

## Later
Move the backend to HTTPS; then delete `res/xml/network_security_config.xml` and its manifest line.
