import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../core/widgets/top_flash.dart';
import 'notification_service.dart';

class LocalNotificationService {
  static final LocalNotificationService to = LocalNotificationService._();
  LocalNotificationService._();

  final _storage = GetStorage();

  static const int _idInactivity     = 4;

  static const _chWelcome = 'food_fit_welcome';
  static const _chNudge   = 'food_fit_nudge';
  static const chSmart    = 'food_fit_smart'; // ใช้โดย DailyNotificationEngine

  Future<void> init() async {
    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: _chWelcome,
          channelName: 'Welcome',
          channelDescription: 'Welcome notification',
          importance: NotificationImportance.High,
        ),
        NotificationChannel(
          channelKey: _chNudge,
          channelName: 'Inactivity Nudge',
          channelDescription: 'Reminder when inactive for 2 days',
          importance: NotificationImportance.Default,
          playSound: false,
        ),
        NotificationChannel(
          channelKey: chSmart,
          channelName: 'Smart Daily Reminder',
          channelDescription: 'Meal and workout reminders based on today\'s progress',
          importance: NotificationImportance.High,
          playSound: true,
          enableVibration: true,
        ),
      ],
      debug: false,
    );

    await AwesomeNotifications().setListeners(
      onActionReceivedMethod: LocalNotificationService.onActionReceivedMethod,
      onNotificationDisplayedMethod: LocalNotificationService.onNotificationDisplayedMethod,
    );

    final allowed = await AwesomeNotifications().isNotificationAllowed();
    if (!allowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }
  }

  @pragma('vm:entry-point')
  static Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
    try {
      final route = receivedAction.payload?['route'] ?? '';
      if (route == 'workout')   NotificationService.to.targetTab.value = 2;
      if (route == 'nutrition') NotificationService.to.targetTab.value = 1;
    } catch (_) {}
  }

  // บันทึกลงประวัติแจ้งเตือน local ทุกครั้งที่มีการแจ้งเตือนแสดงขึ้นจริงบนเครื่อง
  // (ทำงานแม้แอปอยู่เบื้องหลัง/ปิดอยู่ — ตรงข้ามกับ onActionReceivedMethod ที่ทำงานเมื่อกดแตะเท่านั้น)
  @pragma('vm:entry-point')
  static Future<void> onNotificationDisplayedMethod(ReceivedNotification receivedNotification) async {
    try {
      final route = receivedNotification.payload?['route'] ?? 'bell';
      NotificationService.to.addNotification(
        type: route,
        title: receivedNotification.title ?? '',
        body: receivedNotification.body ?? '',
        icon: route,
      );
    } catch (_) {}
  }

  // ── Welcome — ครั้งแรกของอุปกรณ์เท่านั้น ─────────────────────────────────

  Future<void> showWelcome(String name) async {
    if (_storage.read<bool>('notif_welcome_ever') == true) return;
    _storage.write('notif_welcome_ever', true);
    // รอให้ navigation เสร็จก่อนแสดง alert
    await Future.delayed(const Duration(milliseconds: 900));

    // Get.context อาจยังไม่พร้อม ณ จุดนี้ (เรียกจาก background/local notification callback)
    // รอ poll เพิ่มอีกสักพักก่อนยอมแพ้ — ไม่ fallback ไปใช้ SnackBar เพื่อคงมาตรฐาน showAppAlert เดียวทั้งแอป
    BuildContext? ctx = Get.context;
    var attempts = 0;
    while (ctx == null && attempts < 5) {
      await Future.delayed(const Duration(milliseconds: 500));
      ctx = Get.context;
      attempts++;
    }
    if (ctx == null) return;

    showAppAlert(
      ctx,
      '🎉 ยินดีต้อนรับ${name.isNotEmpty ? ", $name" : ""}! เริ่มต้นด้วยการเลือกแผนออกกำลังกายแรกของคุณ 💪',
      type: AppAlertType.success,
    );
  }

  // ── Inactivity nudge — reset ทุกครั้งที่เปิดแอพ ──────────────────────────

  Future<void> _resetInactivityNudge() async {
    await AwesomeNotifications().cancel(_idInactivity);
    final trigger = DateTime.now().add(const Duration(days: 2));
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _idInactivity,
        channelKey: _chNudge,
        title: '🔥 คิดถึงนะ!',
        body: 'ไม่ได้เจอกัน 2 วันแล้ว กลับมาออกกำลังกายต่อได้เลย',
        payload: {'route': 'workout'},
      ),
      schedule: NotificationCalendar(
        year: trigger.year,
        month: trigger.month,
        day: trigger.day,
        hour: 10, minute: 0, second: 0,
        repeats: false,
        allowWhileIdle: true,
      ),
    );
  }

  // ── เรียกตอนเปิดแอพ ───────────────────────────────────────────────────────

  Future<void> checkWorkoutReminder({
    required bool hasActivePlan,
    BuildContext? context,
  }) async {
    if (hasActivePlan) {
      final today = _todayStr();
      if (_storage.read<String>('workout_notif_date') != today) {
        _storage.write('workout_notif_date', today);
        await NotificationService.to.refreshCount();
      }
    }
    await _resetInactivityNudge();
  }

  // ── ยกเลิกทั้งหมดตอน logout ─────────────────────────────────────────────

  Future<void> cancelAll() async {
    await AwesomeNotifications().cancelAll();
    _storage.remove('workout_notif_date');
    // หมายเหตุ: 'notif_welcome_ever' ไม่ลบ — welcome แสดงครั้งเดียวต่ออุปกรณ์
  }

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }
}
