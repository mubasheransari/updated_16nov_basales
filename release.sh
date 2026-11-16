#!/usr/bin/env bash
# One-command Play Store build for BA Sales (com.sales.ba). Run from the project root on your Mac.
set -euo pipefail
cd "$(dirname "$0")"

EXPECTED_SHA1="78:0F:E0:5B:C4:75:E5:59:F2:FF:E7:E8:CA:F7:2C:BF:D1:F1:83:15"
red(){ printf "\033[31m%s\033[0m\n" "$*"; }; grn(){ printf "\033[32m%s\033[0m\n" "$*"; }
die(){ red "ERROR: $*"; exit 1; }

# 1. Signing config
[ -f android/key.properties ] || die "android/key.properties missing (copy android/key.properties.example)."
prop(){ grep -E "^$1=" android/key.properties | head -1 | cut -d= -f2-; }
STORE_FILE="$(prop storeFile)"; STORE_PASS="$(prop storePassword)"; KEY_PASS="$(prop keyPassword)"; ALIAS="$(prop keyAlias)"
case "$STORE_PASS$KEY_PASS" in *YOUR_KEYSTORE_PASSWORD*) die "Put your real keystore password in android/key.properties";; esac
[ -f "$STORE_FILE" ] || die "Keystore not found at: $STORE_FILE  (move your .jks there or fix storeFile=)"

# 2. Verify the keystore is the expected upload key
SHA1="$(keytool -list -v -keystore "$STORE_FILE" -alias "$ALIAS" -storepass "$STORE_PASS" 2>&1 | grep -m1 'SHA1:' | awk '{print $2}')" || true
[ -n "$SHA1" ] || die "Could not open keystore (wrong password or alias '$ALIAS')."
[ "$SHA1" = "$EXPECTED_SHA1" ] || die "Keystore SHA1 is $SHA1, expected $EXPECTED_SHA1 - wrong keystore?"
grn "Keystore OK (alias $ALIAS, SHA1 matches upload key)."

# 3. Maps key
grep -Eq '^MAPS_API_KEY=AIza' android/local.properties || die "Set a real MAPS_API_KEY=AIza... in android/local.properties"

# 4. Build
flutter clean
flutter pub get
dart run flutter_launcher_icons
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build appbundle --release
flutter build apk --release

# 5. Confirm the AAB is signed with the upload key
AAB=build/app/outputs/bundle/release/app-release.aab
OUT="$(keytool -printcert -jarfile "$AAB" 2>&1)"
echo "$OUT" | grep -q "$EXPECTED_SHA1" || die "AAB is NOT signed with the upload key!"
grn "AAB signed with upload key."
grn "Upload: $AAB"
grn "Test on a phone first: build/app/outputs/flutter-apk/app-release.apk"
