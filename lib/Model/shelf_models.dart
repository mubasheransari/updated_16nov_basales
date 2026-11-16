// Models for the Shelf Images screen. The list endpoint returns metadata only.

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String _str(dynamic v) => v?.toString().trim() ?? '';

class ShelfPicture {
  final int id;
  final DateTime? capturedAt;
  final DateTime? createdAt;
  final String remarks;
  final String locationName;
  final String areaName;
  final String city;
  final String imageMimeType;
  final double? latitude;
  final double? longitude;

  const ShelfPicture({
    required this.id,
    required this.capturedAt,
    required this.createdAt,
    required this.remarks,
    required this.locationName,
    required this.areaName,
    required this.city,
    required this.imageMimeType,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'picture_id': id,
        'captured_at': capturedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'remarks': remarks,
        'mart_name': locationName,
        'area_name': areaName,
        'city': city,
        'image_mime_type': imageMimeType,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory ShelfPicture.fromJson(Map<String, dynamic> json) {
    final m = {for (final e in json.entries) e.key.toLowerCase(): e.value};
    DateTime? parseDate(dynamic value) {
      final s = _str(value);
      // Oracle returns the timestamp with its timezone offset (for example, +05:00).
      // Dart parses offset timestamps as UTC; convert to the device's local timezone
      // before displaying so Pakistan time remains 07:17 instead of 02:17.
      return s.isEmpty ? null : DateTime.tryParse(s)?.toLocal();
    }
    double? parseDouble(dynamic value) =>
        value == null ? null : double.tryParse(value.toString());

    return ShelfPicture(
      id: _int(m['picture_id'] ?? m['id']),
      capturedAt: parseDate(m['captured_at']),
      createdAt: parseDate(m['created_at']),
      remarks: _str(m['remarks']),
      locationName: _str(m['mart_name'] ?? m['location_name']),
      areaName: _str(m['area_name']),
      city: _str(m['city']),
      imageMimeType: _str(m['image_mime_type']),
      latitude: parseDouble(m['latitude']),
      longitude: parseDouble(m['longitude']),
    );
  }
}
