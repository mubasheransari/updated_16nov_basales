# BA Sales V2 – Device Update, Offline Queue and UI Updates

## Included changes

### Device ID update
- Added `auth/device-id/check/` and `auth/device-id/update/` endpoint constants.
- Checks the current device ID on the unauthenticated login screen and after a saved session is restored.
- Shows the device update bottom sheet only when the check API returns `registered: false`.
- The sheet contains Full Name, CNIC and the automatically detected read-only Device ID.
- Reuses the existing `/auth/check-ba-cnic/` repository method.
- Requires the entered full name to match the name returned by the CNIC verification response.
- Calls `/auth/device-id/update/` only after successful CNIC verification.
- After an update from an already-authenticated session, the app asks the user to log in again.

Expected API contracts:
- Check: `{ "device_id": "..." }` -> response contains `registered: true|false`.
- Update: `{ "full_name": "...", "cnic": "13 digits", "device_id": "..." }` -> response contains `updated: true`.

The update API must perform its own CNIC/account validation and must not trust client-side verification alone.

### Offline submissions
The app already persisted attendance, product catalog, cart and sales history locally. This update adds a BA-scoped durable queue for:
- Sales submissions
- Complaints (including optional photo)
- Leave requests
- Shelf picture uploads

Network-unavailable submissions are saved locally and retried:
- when the app is opened into the authenticated shell,
- when the app returns to the foreground,
- when the user pulls down to refresh the home dashboard.

The queue retains failed items. It removes an item only after the corresponding API call succeeds. A local sale is also written to sales history immediately so the dashboard/history can show it while offline.

Important:
- Attendance IN is still expected to have been successfully recorded before offline work begins; sales and shelf capture retain the existing attendance-IN gate.
- Product catalog and mart locations use the existing cache fallback.
- This is an offline submission queue, not an offline Oracle database. Items remain pending on the phone until the server accepts them.
- Reconnection retry is triggered by app resume or manual pull-to-refresh; no background connectivity listener has been added.

### UI
- Daily Sales and Shelf Images action cards now use a dark navy gradient.
- Sales history groups all sales entries by date into one expandable daily card, with individual entries nested inside.
- Sales chart has a softer chart plotting surface and retains the existing period filters, animations, selected-bar details and summary statistics.

## Files changed
- `lib/Api_config/api_config.dart`
- `lib/Repository/repository.dart`
- `lib/Data/local_store.dart`
- `lib/Screens/auth_screen.dart`
- `lib/Screens/device_update_sheet.dart` (new)
- `lib/Screens/app_shell.dart`
- `lib/Screens/home_screen.dart`
- `lib/Screens/products.dart`
- `lib/Screens/new_complaint_screen.dart`
- `lib/Screens/new_leave_screen.dart`
- `lib/Screens/history_screen.dart`
- `lib/Bloc/attendance_cubit.dart`
- `lib/Widgets/shelf_dialog.dart`
- `lib/Widgets/sales_chart.dart`

## Validation
The archive was checked for balanced Dart delimiters and expected endpoint references. A Flutter/Dart SDK was not available in the execution environment, so `flutter analyze`, Android build and iOS build have not been run. Run `flutter pub get` and `flutter analyze` in your development environment before release.
