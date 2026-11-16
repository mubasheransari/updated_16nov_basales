import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ords_ba/Api_config/api_config.dart';

/// App-wide online/offline state. The repository flips it on every request:
/// no response from the server => offline, any response => online. While
/// offline, the server host is probed every few seconds so the banner goes
/// away (and queued work can sync) as soon as the internet is back.
class NetworkStatus {
  NetworkStatus._();

  static final ValueNotifier<bool> offline = ValueNotifier<bool>(false);
  static Timer? _probe;

  static const message = "You're in offline mode. No internet connection.";

  static void markOffline() {
    if (!offline.value) offline.value = true;
    _probe ??= Timer.periodic(const Duration(seconds: 8), (_) => _check());
  }

  static void markOnline() {
    if (offline.value) offline.value = false;
    _probe?.cancel();
    _probe = null;
  }

  static Future<void> _check() async {
    try {
      final host = Uri.parse(ApiConfig.base).host;
      final r = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 4));
      if (r.isNotEmpty && r.first.rawAddress.isNotEmpty) markOnline();
    } catch (_) {
      // still offline
    }
  }
}
