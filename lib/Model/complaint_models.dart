// Models for the Complaints / Problems feature (no chat for now).

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String _str(dynamic v) => v?.toString() ?? '';

/// One complaint raised by the BA.
class Complaint {
  final int id;
  final String title;
  final String status; // OPEN | RESOLVED
  final String description;
  final DateTime? createdAt;
  final String locationName;

  const Complaint({
    required this.id,
    required this.title,
    required this.status,
    required this.description,
    required this.createdAt,
    required this.locationName,
  });

  bool get isOpen => status.toUpperCase() != 'RESOLVED';

  factory Complaint.fromJson(Map<String, dynamic> j) => Complaint(
        id: _int(j['complaint_id']),
        title: _str(j['title']),
        status: _str(j['status']).toUpperCase(),
        // The list handler returns the text as `description` or `snippet`.
        description: _str(j['description'] ?? j['snippet']),
        createdAt: _date(j['created_at'] ?? j['last_message_at']),
        locationName: _str(j['location_name']),
      );
}
