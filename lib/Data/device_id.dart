import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';

/// Stable device identifier used by the BA account device-binding feature.
///
/// Android: hashed Widevine device id. It belongs to the phone, so it is the
/// same in debug, release and Play builds and survives uninstall/reinstall.
/// Phones without Widevine fall back to Android ID. A factory reset changes it.
///
/// iOS: Uses identifierForVendor.
class DeviceId {
  DeviceId._();

  static const _channel = MethodChannel('com.sales.ba/device');
  static const _kSaved = 'device_id_v2';
  static String _value = '';

  static String get value => _value;
  static bool get isReady => _value.isNotEmpty;

  static Future<String> load() async {
    if (_value.isNotEmpty) return _value;

    // Saved so the value can never flip between runs of the same install.
    final box = GetStorage();
    final saved = _clean(box.read<String>(_kSaved));
    if (saved.isNotEmpty) {
      _value = saved;
      return _value;
    }

    String? rawId;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // 1) Hashed Widevine device id: same for debug, release and Play builds
        //    and after uninstall/reinstall.
        try {
          rawId = await _channel.invokeMethod<String>('getStableId');
        } catch (_) {
          rawId = null;
        }
        // 2) Phones without Widevine only: Android ID (depends on signing key).
        if (rawId == null || rawId.trim().isEmpty) {
          rawId = await const AndroidId().getId();
        }
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        rawId = (await DeviceInfoPlugin().iosInfo).identifierForVendor;
      }
    } catch (e) {
      throw StateError('Unable to read this device identifier: $e');
    }

    final cleanId = _clean(rawId);
    if (cleanId.isEmpty) {
      // Do not silently generate a random ID. Random IDs stored in app data
      // are deleted on uninstall and can cause a BA device binding mismatch.
      throw StateError(
        'The device identifier is unavailable. Please restart the app and try again.',
      );
    }

    _value = cleanId;
    await box.write(_kSaved, cleanId);
    return _value;
  }

  /// Keep the identifier safe for HTTP headers and the existing API payload.
  static String _clean(String? raw) {
    final value = (raw ?? '').trim().replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '',
    );
    return value.length > 64 ? value.substring(0, 64) : value;
  }
}
