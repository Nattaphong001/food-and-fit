// AppNotification — ประวัติแจ้งเตือนที่เก็บไว้ในเครื่อง (local-only) ไม่ผูกกับ backend
// เพราะตาราง member_notifications ถูกลบออกจาก backend แล้ว (2026-08-11)

class AppNotification {
  final int ntfId;
  final String ntfType;
  final String ntfTitle;
  final String ntfBody;
  final String ntfIcon;
  final bool isRead;
  final String ntfDate;
  final DateTime createdAt;

  AppNotification({
    required this.ntfId,
    required this.ntfType,
    required this.ntfTitle,
    required this.ntfBody,
    required this.ntfIcon,
    required this.isRead,
    required this.ntfDate,
    required this.createdAt,
  });

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      ntfId: ntfId,
      ntfType: ntfType,
      ntfTitle: ntfTitle,
      ntfBody: ntfBody,
      ntfIcon: ntfIcon,
      isRead: isRead ?? this.isRead,
      ntfDate: ntfDate,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'ntf_id': ntfId,
        'ntf_type': ntfType,
        'ntf_title': ntfTitle,
        'ntf_body': ntfBody,
        'ntf_icon': ntfIcon,
        'is_read': isRead,
        'ntf_date': ntfDate,
        'created_at': createdAt.toIso8601String(),
      };

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      ntfId: map['ntf_id'] ?? 0,
      ntfType: map['ntf_type'] ?? '',
      ntfTitle: map['ntf_title'] ?? '',
      ntfBody: map['ntf_body'] ?? '',
      ntfIcon: map['ntf_icon'] ?? 'bell',
      isRead: map['is_read'] == true,
      ntfDate: map['ntf_date'] ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
