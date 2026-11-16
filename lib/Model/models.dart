import 'dart:convert';
import 'package:flutter/foundation.dart';



num? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString().trim());
}

int? _int(dynamic v) => _num(v)?.toInt();

double? _dbl(dynamic v) => _num(v)?.toDouble();

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/* ------------------------------------------------------------------ */
/*  Location (mart)                                                     */
/* ------------------------------------------------------------------ */
class MartLocation {
  final int id;
  final String name;
  final String areaName;
  final String city;
  final double? latitude;
  final double? longitude;
  final DateTime? createdAt;
  final double radiusMeters;

  const MartLocation({
    required this.id,
    required this.name,
    required this.areaName,
    required this.city,
    this.latitude,
    this.longitude,
    this.createdAt,
    this.radiusMeters = 100,
  });

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  factory MartLocation.fromJson(Map<String, dynamic> json) {
    dynamic field(String key) {
      for (final entry in json.entries) {
        if (entry.key.trim().toLowerCase() == key.toLowerCase()) {
          return entry.value;
        }
      }
      return null;
    }

    return MartLocation(
      id: _int(field('location_id') ?? field('id')) ?? 0,
      name: _str(field('mart_name') ?? field('location_name')) ?? '',
      areaName: _str(field('area_name')) ?? '',
      city: _str(field('city')) ?? '',
      latitude: _dbl(field('latitude')),
      longitude: _dbl(field('longitude')),
      createdAt: DateTime.tryParse(
        field('created_at')?.toString() ?? '',
      ),
      radiusMeters: _dbl(field('radius_meters')) ?? 100,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'location_id': id,
      'mart_name': name,
      'area_name': areaName,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt?.toIso8601String(),
      'radius_meters': radiusMeters,
    };
  }
}



class AppUser {
  final String id;
  final String fullName;
  final String email;
  final String? cnic;
  final String role;
  final int? locationId;
  final String? locationName;
  final String? areaName;
  final String? city;
  final double? latitude;
  final double? longitude;

  // Y = attendance can be marked anywhere.
  // N = attendance is restricted to the assigned mart radius.
  final bool attendanceAnywhere;

  // Indicates whether the API actually supplied this field.
  final bool attendanceAnywhereProvided;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.cnic,
    this.role = 'BA',
    this.locationId,
    this.locationName,
    this.areaName,
    this.city,
    this.latitude,
    this.longitude,
    this.attendanceAnywhere = false,
    this.attendanceAnywhereProvided = false,
  });

  String get storageKey => (email.isNotEmpty ? email : id)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '_');

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  static bool _parseAttendanceAnywhere(dynamic value) {
    if (value == true) return true;
    if (value == false || value == null) return false;

    if (value is num) {
      return value == 1;
    }

    final normalized = value.toString().trim().toUpperCase();

    return normalized == 'Y' ||
        normalized == 'YES' ||
        normalized == 'TRUE' ||
        normalized == '1';
  }

  /// Searches case-insensitively through nested JSON maps and lists.
  ///
  /// Supports:
  /// {
  ///   "attendance_anywhere": "Y"
  /// }
  ///
  /// Also supports:
  /// {
  ///   "data": {
  ///     "user": {
  ///       "attendance_anywhere": "Y"
  ///     }
  ///   }
  /// }
  ///
  /// And ORDS-style:
  /// {
  ///   "items": [
  ///     {
  ///       "attendance_anywhere": "Y"
  ///     }
  ///   ]
  /// }
  static dynamic _find(
    Map<String, dynamic> map,
    List<String> keys, {
    int depth = 0,
  }) {
    if (depth > 8) return null;

    // First search the current map.
    for (final wanted in keys) {
      for (final entry in map.entries) {
        if (entry.key.trim().toLowerCase() ==
            wanted.trim().toLowerCase()) {
          if (entry.value != null) {
            return entry.value;
          }
        }
      }
    }

    // Then search nested maps and lists.
    for (final entry in map.entries) {
      final value = entry.value;

      if (value is Map) {
        final result = _find(
          Map<String, dynamic>.from(value),
          keys,
          depth: depth + 1,
        );

        if (result != null) return result;
      } else if (value is List) {
        for (final item in value) {
          if (item is Map) {
            final result = _find(
              Map<String, dynamic>.from(item),
              keys,
              depth: depth + 1,
            );

            if (result != null) return result;
          }
        }
      }
    }

    return null;
  }

  static double? _readDouble(dynamic value) {
    return _dbl(value);
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final rawLocation = _find(json, [
      'location',
    ]);

    final location = rawLocation is Map
        ? Map<String, dynamic>.from(rawLocation)
        : <String, dynamic>{};

    final rawAttendanceAnywhere = _find(json, [
      'attendance_anywhere',
      'ATTENDANCE_ANYWHERE',
      'attendanceAnywhere',
    ]);

    final attendanceAnywhereProvided =
        rawAttendanceAnywhere != null;

    final rawId = _find(json, [
      'user_id',
      'id',
      'ba_id',
      'emp_id',
    ]);

    final rawLocationId =
        _find(location, [
          'location_id',
          'id',
        ]) ??
        _find(json, [
          'location_id',
        ]);

    final rawLocationName =
        _find(location, [
          'mart_name',
          'location_name',
          'name',
        ]) ??
        _find(json, [
          'location_name',
          'mart_name',
        ]);

    final rawFullName = _find(json, [
      'full_name',
      'name',
      'user_name',
    ]);

    final rawEmail = _find(json, [
      'email',
    ]);

    final rawCnic = _find(json, [
      'cnic',
    ]);

    final rawRole = _find(json, [
      'role_code',
      'role',
    ]);

    final rawAreaName =
        _find(location, [
          'area_name',
          'area',
        ]) ??
        _find(json, [
          'area_name',
        ]);

    final rawCity =
        _find(location, [
          'city',
        ]) ??
        _find(json, [
          'city',
        ]);

    final rawLatitude =
        _find(location, [
          'latitude',
        ]) ??
        _find(json, [
          'latitude',
        ]);

    final rawLongitude =
        _find(location, [
          'longitude',
        ]) ??
        _find(json, [
          'longitude',
        ]);

    final user = AppUser(
      id: rawId?.toString().trim() ?? '',
      fullName: rawFullName?.toString().trim().isNotEmpty == true
          ? rawFullName.toString().trim()
          : 'BA',
      email: rawEmail?.toString().trim() ?? '',
      cnic: _str(rawCnic),
      role: rawRole?.toString().trim().isNotEmpty == true
          ? rawRole.toString().trim()
          : 'BA',
      locationId: _int(rawLocationId),
      locationName: _str(rawLocationName),
      areaName: _str(rawAreaName),
      city: _str(rawCity),
      latitude: _readDouble(rawLatitude),
      longitude: _readDouble(rawLongitude),
      attendanceAnywhere:
          _parseAttendanceAnywhere(rawAttendanceAnywhere),
      attendanceAnywhereProvided:
          attendanceAnywhereProvided,
    );

    // Debug logs: remove after confirming the API response.
    debugPrint('========== APP USER MODEL DEBUG ==========');
    debugPrint('User ID: ${user.id}');
    debugPrint('User Name: ${user.fullName}');
    debugPrint('Email: ${user.email}');
    debugPrint('Location ID: ${user.locationId}');
    debugPrint(
      'Raw attendance_anywhere: $rawAttendanceAnywhere',
    );
    debugPrint(
      'Attendance field provided: ${user.attendanceAnywhereProvided}',
    );
    debugPrint(
      'Parsed attendanceAnywhere: ${user.attendanceAnywhere}',
    );
    debugPrint('==========================================');

    return user;
  }

  Map<String, dynamic> toJson() => {
        'user_id': id,
        'full_name': fullName,
        'email': email,
        'cnic': cnic,
        'role_code': role,
        'location_id': locationId,
        'location_name': locationName,
        'area_name': areaName,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        // Cache the permission ONLY when the server actually supplied it.
        // Writing a default 'N' here poisons the cache: on the next launch
        // it is read back as an explicit server value and overrides 'Y'.
        // Stored under a new key so old poisoned caches are ignored.
        if (attendanceAnywhereProvided)
          'aa_cache_v2': attendanceAnywhere ? 'Y' : 'N',
      };

  /// A fresh explicit server value replaces the old value.
  /// If the response omits the field, preserve the previous value.
  AppUser mergeWith(AppUser other) => AppUser(
        id: other.id.isNotEmpty ? other.id : id,
        fullName: other.fullName != 'BA'
            ? other.fullName
            : fullName,
        email: other.email.isNotEmpty ? other.email : email,
        cnic: other.cnic ?? cnic,
        role: other.role.isNotEmpty ? other.role : role,
        locationId: other.locationId ?? locationId,
        locationName: other.locationName ?? locationName,
        areaName: other.areaName ?? areaName,
        city: other.city ?? city,
        latitude: other.latitude ?? latitude,
        longitude: other.longitude ?? longitude,
        attendanceAnywhere: other.attendanceAnywhereProvided
            ? other.attendanceAnywhere
            : attendanceAnywhere,
        attendanceAnywhereProvided:
            other.attendanceAnywhereProvided ||
                attendanceAnywhereProvided,
      );

  AppUser withLocationName(String? name) => AppUser(
        id: id,
        fullName: fullName,
        email: email,
        cnic: cnic,
        role: role,
        locationId: locationId,
        locationName: name ?? locationName,
        areaName: areaName,
        city: city,
        latitude: latitude,
        longitude: longitude,
        attendanceAnywhere: attendanceAnywhere,
        attendanceAnywhereProvided: attendanceAnywhereProvided,
      );
}

class Sku {
  final int skuId;
  final String itemCode;
  final String itemName;
  final String blendName;
  final String group;

  const Sku({
    required this.skuId,
    required this.itemCode,
    required this.itemName,
    required this.blendName,
    required this.group,
  });

  /// Uses `con_blend_name` (consolidated blend) when present, otherwise
  /// `blend_name`. Names are trimmed - some come with a leading space
  /// (e.g. " AWAZ").
  // ORDS may emit column names in uppercase (SKU_ID) or lowercase
  // (sku_id), depending on the handler/serialization. Read both safely.
  factory Sku.fromJson(Map<String, dynamic> j) {
    dynamic field(String name) {
      if (j.containsKey(name)) return j[name];
      final upper = name.toUpperCase();
      if (j.containsKey(upper)) return j[upper];
      final lower = name.toLowerCase();
      if (j.containsKey(lower)) return j[lower];
      return null;
    }

    final blend = _str(field('con_blend_name')) ??
        _str(field('blend_name')) ??
        '';
    final group = _str(field('sku_group')) ?? blend;
    final rawSkuId = field('sku_id') ?? field('item_code');
    return Sku(
      skuId: _int(rawSkuId) ?? 0,
      itemCode: _str(field('item_code')) ?? '',
      itemName: _str(field('item_name')) ?? 'Unknown item',
      blendName: blend,
      group: group,
    );
  }

  Map<String, dynamic> toJson() => {
        'sku_id': skuId,
        'item_code': itemCode,
        'item_name': itemName,
        'con_blend_name': blendName,
        'sku_group': group,
        'active': 'Y',
      };

  static bool isActive(Map<String, dynamic> j) {
    // ORDS may return aliases in different cases, or expose ACTIVE_FLAG
    // instead of ACTIVE. Fail closed: missing/null status is NOT active.
    dynamic raw;
    for (final entry in j.entries) {
      final key = entry.key.toString().trim().toUpperCase();
      if (key == 'ACTIVE' || key == 'ACTIVE_FLAG') {
        raw = entry.value;
        break;
      }
    }

    final value = raw?.toString().trim().toUpperCase();
    return value == 'Y' ||
        value == '1' ||
        value == 'TRUE' ||
        value == 'YES';
  }
}

/* ------------------------------------------------------------------ */
/*  Attendance (local record)                                           */
/* ------------------------------------------------------------------ */

class AttendanceRecord {
  /// yyyy-MM-dd
  final String date;
  final DateTime inAt;
  final DateTime? outAt;

  /// True when the out time was set automatically at 12:00 AM.
  final bool autoOut;
  final double? inLat;
  final double? inLng;
  final String? locationName;

  const AttendanceRecord({
    required this.date,
    required this.inAt,
    this.outAt,
    this.autoOut = false,
    this.inLat,
    this.inLng,
    this.locationName,
  });

  bool get isOpen => outAt == null;

  AttendanceRecord copyWith({DateTime? outAt, bool? autoOut}) =>
      AttendanceRecord(
        date: date,
        inAt: inAt,
        outAt: outAt ?? this.outAt,
        autoOut: autoOut ?? this.autoOut,
        inLat: inLat,
        inLng: inLng,
        locationName: locationName,
      );

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) =>
      AttendanceRecord(
        date: j['date'].toString(),
        inAt: DateTime.parse(j['in'].toString()),
        outAt: j['out'] == null ? null : DateTime.tryParse(j['out'].toString()),
        autoOut: j['auto_out'] == true,
        inLat: _dbl(j['in_lat']),
        inLng: _dbl(j['in_lng']),
        locationName: _str(j['location_name']),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'in': inAt.toIso8601String(),
        'out': outAt?.toIso8601String(),
        'auto_out': autoOut,
        'in_lat': inLat,
        'in_lng': inLng,
        'location_name': locationName,
      };
}

/* ------------------------------------------------------------------ */
/*  Sale (local history)                                                */
/* ------------------------------------------------------------------ */

class SaleLine {
  final int skuId;
  final String name;
  final String blend;
  final int qty;
  const SaleLine({
    required this.skuId,
    required this.name,
    required this.blend,
    required this.qty,
  });

  factory SaleLine.fromJson(Map<String, dynamic> j) => SaleLine(
        skuId: _int(j['sku_id']) ?? 0,
        name: _str(j['name']) ?? '',
        blend: _str(j['blend']) ?? '',
        qty: _int(j['qty']) ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'sku_id': skuId, 'name': name, 'blend': blend, 'qty': qty};
}

class SaleRecord {
  final String id;
  final DateTime createdAt;
  final String saleDate; // yyyy-MM-dd (what was sent to the API)
  final int? locationId;
  final List<SaleLine> lines;

  const SaleRecord({
    required this.id,
    required this.createdAt,
    required this.saleDate,
    required this.locationId,
    required this.lines,
  });

  int get totalQty => lines.fold(0, (a, b) => a + b.qty);

  factory SaleRecord.fromJson(Map<String, dynamic> j) => SaleRecord(
        id: j['id'].toString(),
        createdAt: DateTime.parse(j['created_at'].toString()),
        saleDate: j['sale_date'].toString(),
        locationId: _int(j['location_id']),
        lines: [
          for (final l in (j['lines'] as List? ?? []))
            SaleLine.fromJson(Map<String, dynamic>.from(l as Map)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'sale_date': saleDate,
        'location_id': locationId,
        'lines': [for (final l in lines) l.toJson()],
      };

  @override
  String toString() => jsonEncode(toJson());
}