// NotificationService — ประวัติแจ้งเตือนแบบ local-only เก็บใน GetStorage บนเครื่อง
// ไม่เรียก backend อีกต่อไป เพราะตาราง member_notifications + endpoint /notifications/*
// ถูกลบออกจาก backend แล้ว (2026-08-11) รายการถูกเติมโดย LocalNotificationService
// ทุกครั้งที่มีการแจ้งเตือนแสดงขึ้นจริงบนเครื่อง (ผ่าน awesome_notifications)
//
// เก็บแบบรายวัน (key ผูกกับวันที่) เพื่อประหยัดพื้นที่ — ของเก่าข้ามวันถูกล้างทิ้งอัตโนมัติ
// ตอนอ่านครั้งแรกของวันใหม่ ไม่มี background job ใดๆ ทำหน้าที่เคลียร์
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../models/notification_model.dart';

class NotificationService extends GetxService {
  static NotificationService get to => Get.find();

  final _storage = GetStorage();
  static const _storageKeyPrefix = 'daily_notif_';
  static const _lastDateKey = 'daily_notif_last_date';
  static const _maxHistory = 100;

  final unreadCount = 0.obs;
  final targetTab = RxnInt(); // shell จะ listen และ switch tab เมื่อ != null

  @override
  void onInit() {
    super.onInit();
    _purgeStaleDays();
    _recomputeUnreadCount();
  }

  String _todayStr() => _dateStr(DateTime.now());

  String get _storageKey => '$_storageKeyPrefix${_todayStr()}';

  // ลบ key ของวันก่อนหน้าทิ้ง เก็บไว้เฉพาะของวันนี้
  void _purgeStaleDays() {
    final today = _todayStr();
    final lastDate = _storage.read<String>(_lastDateKey);
    if (lastDate != null && lastDate != today) {
      _storage.remove('$_storageKeyPrefix$lastDate');
    }
    _storage.write(_lastDateKey, today);
  }

  List<AppNotification> _readAll() {
    _purgeStaleDays();
    final raw = _storage.read<List>(_storageKey) ?? [];
    final list = raw
        .map((e) => AppNotification.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  void _writeAll(List<AppNotification> list) {
    _storage.write(_storageKey, list.map((n) => n.toMap()).toList());
    _recomputeUnreadCount();
  }

  void _recomputeUnreadCount() {
    unreadCount.value = _readAll().where((n) => !n.isRead).length;
  }

  // เรียกจาก LocalNotificationService ทุกครั้งที่มีการแจ้งเตือนแสดงขึ้นจริงบนเครื่อง
  void addNotification({
    required String type,
    required String title,
    required String body,
    String icon = 'bell',
  }) {
    final now = DateTime.now();
    final list = _readAll();
    list.insert(
      0,
      AppNotification(
        ntfId: now.microsecondsSinceEpoch,
        ntfType: type,
        ntfTitle: title,
        ntfBody: body,
        ntfIcon: icon,
        isRead: false,
        ntfDate: _dateStr(now),
        createdAt: now,
      ),
    );
    _writeAll(list.take(_maxHistory).toList());
  }

  Future<List<AppNotification>> getNotifications() async => _readAll();

  Future<void> markOneRead(int id) async {
    final list = _readAll();
    final idx = list.indexWhere((n) => n.ntfId == id);
    if (idx == -1) return;
    list[idx] = list[idx].copyWith(isRead: true);
    _writeAll(list);
  }

  Future<void> markAllRead() async {
    _writeAll(_readAll().map((n) => n.copyWith(isRead: true)).toList());
  }

  Future<void> refreshCount() async => _recomputeUnreadCount();

  // เรียกตอน logout — ล้างประวัติแจ้งเตือนของบัญชีเดิมออกจากเครื่อง
  void clearAll() {
    _storage.remove(_storageKey);
    _recomputeUnreadCount();
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
