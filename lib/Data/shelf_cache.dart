import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ords_ba/Api_config/api_config.dart';
import 'package:ords_ba/Data/network_status.dart';
import 'package:ords_ba/Model/shelf_models.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps shelf pictures on the phone so they still open in offline mode.
/// Pictures are stored as files in the app's private storage (one folder per
/// BA); the picture list is kept in local storage.
class ShelfCache {
  ShelfCache(String userKey)
      : _folder = userKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_'),
        _listKey = 'shelf_list_${userKey.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';

  final String _folder;
  final String _listKey;
  final GetStorage _box = GetStorage();

  static const _maxFiles = 150; // oldest files are removed beyond this

  /* ------------------------------- list ------------------------------- */

  Future<void> saveList(List<ShelfPicture> items) => _box.write(
      _listKey, jsonEncode([for (final p in items) p.toJson()]));

  List<ShelfPicture> readList() {
    final raw = _box.read<String>(_listKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          ShelfPicture.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /* ------------------------------ images ------------------------------ */

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/shelf_images/$_folder');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(int id) async => File('${(await _dir()).path}/$id.img');

  Future<Uint8List?> read(int id) async {
    try {
      final f = await _file(id);
      if (await f.exists()) {
        final b = await f.readAsBytes();
        if (b.isNotEmpty) return b;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _write(int id, Uint8List bytes) async {
    try {
      await (await _file(id)).writeAsBytes(bytes, flush: true);
      await _evict();
    } catch (_) {}
  }

  Future<void> _evict() async {
    final files = (await _dir()).listSync().whereType<File>().toList();
    if (files.length <= _maxFiles) return;
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final f in files.take(files.length - _maxFiles)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// Phone copy first (works offline). Otherwise download, save and return.
  /// Throws if the picture is not on the phone and the download fails.
  Future<Uint8List> load(int id, String url, Map<String, String> headers) async {
    final cached = await read(id);
    if (cached != null) return cached;
    final res = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(ApiConfig.uploadTimeout)
        .catchError((Object e) {
      NetworkStatus.markOffline();
      throw e;
    });
    NetworkStatus.markOnline();
    if (res.statusCode < 200 || res.statusCode >= 300 || res.bodyBytes.isEmpty) {
      throw HttpException('Picture request failed (${res.statusCode})');
    }
    await _write(id, res.bodyBytes);
    return res.bodyBytes;
  }

  /// Quietly saves the newest pictures so they are there when offline.
  Future<void> prefetch(List<ShelfPicture> items, String Function(int) urlOf,
      Map<String, String> headers,
      {int limit = 30}) async {
    for (final p in items.take(limit)) {
      if (await read(p.id) != null) continue;
      try {
        await load(p.id, urlOf(p.id), headers);
      } catch (_) {
        return; // offline again: stop
      }
    }
  }
}
