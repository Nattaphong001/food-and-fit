// DailyNotificationEngine — เช็คความคืบหน้าจริงของวันนี้ (แคลอรี่ / ออกกำลังกาย) แล้วยิง
// local push ทันทีถ้ายังไม่ถึงเป้า ทำงานเฉพาะตอนแอปเปิดอยู่ (foreground) เท่านั้น เพราะต้องอ่าน
// ข้อมูลที่เป็นปัจจุบัน ณ ขณะนั้นจาก AnalyticsService — ไม่ใช้ background schedule
//
// กันยิงซ้ำด้วย flag ต่อวันใน GetStorage (key ผูกวันที่ ของเก่าข้ามวันไม่ถูกอ่านอีกจึงไม่ต้องเคลียร์เอง)
// การแสดงผลจริง + บันทึกลงประวัติแจ้งเตือน ทำผ่าน awesome_notifications เหมือนช่องทางอื่น
// (LocalNotificationService.onNotificationDisplayedMethod เป็นตัวบันทึกให้อัตโนมัติอยู่แล้ว)
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:get_storage/get_storage.dart';
import '../models/analytics_model.dart';
import 'analytics_service.dart';
import 'local_notification_service.dart';

class DailyNotificationEngine {
  static final DailyNotificationEngine to = DailyNotificationEngine._();
  DailyNotificationEngine._();

  final _storage = GetStorage();
  static const _flagsKeyPrefix = 'notif_engine_fired_';

  static const _idGreeting         = 10;
  static const _idMealMorning      = 11;
  static const _idMealNoon         = 12;
  static const _idMealEvening      = 13;
  static const _idWorkoutAfternoon = 14;
  static const _idWorkoutEvening   = 15;

  Future<void> check() async {
    final fired = _readFired();
    final hour = DateTime.now().hour;

    if (!fired.contains('greeting')) {
      await _notify(_idGreeting, 'bell', '👋 สวัสดี เริ่มวันใหม่กันเลย!',
          'มาดูแลสุขภาพวันนี้ให้ดีที่สุดกัน');
      _markFired('greeting');
    }

    final r = await AnalyticsService.to.getDailyAnalytics();
    if (r['success'] != true) return;
    final daily = r['data'] as DailyAnalytics;

    if (daily.targetTdee > 0) {
      await _checkMeal(hour, fired, daily.totalCaloriesIn, daily.targetTdee);
    }
    await _checkWorkout(hour, fired, daily.exerciseBurn);
  }

  // แบ่งช่วงเวลาตามเวลาปัจจุบันที่เปิดแอป เทียบสัดส่วนแคลอรี่ที่ "ควรกินไปแล้ว" ของช่วงนั้น
  Future<void> _checkMeal(int hour, Set<String> fired, double eaten, double target) async {
    late final String window;
    late final double expectedRatio;
    late final int id;
    late final String title;
    late final String body;

    if (hour >= 19) {
      window = 'evening'; expectedRatio = 0.9; id = _idMealEvening;
      title = '🌙 ใกล้หมดวันแล้ว แคลอรี่วันนี้ยังไม่ครบเป้า';
      body  = 'เช็คมื้ออาหารวันนี้อีกครั้งก่อนนอน';
    } else if (hour >= 13) {
      window = 'noon'; expectedRatio = 0.6; id = _idMealNoon;
      title = '🥗 แคลอรี่วันนี้ยังไม่ถึงเป้า';
      body  = 'อย่าลืมบันทึกมื้อเที่ยงด้วยนะ';
    } else if (hour >= 10) {
      window = 'morning'; expectedRatio = 0.25; id = _idMealMorning;
      title = '🍽️ ยังไม่ได้กินอาหารเช้าเลยนะ';
      body  = 'บันทึกมื้อเช้าเพื่อให้ได้แคลอรี่ตามเป้าหมายวันนี้';
    } else {
      return; // ยังเช้ามืดเกินไป ไม่ต้องเตือน
    }

    final flag = 'meal_$window';
    if (fired.contains(flag)) return;
    if (eaten >= target * expectedRatio) return;

    await _notify(id, 'nutrition', title, body);
    _markFired(flag);
  }

  Future<void> _checkWorkout(int hour, Set<String> fired, double burn) async {
    if (burn > 0) return; // ออกกำลังกายแล้ววันนี้ ไม่ต้องเตือน

    late final String window;
    late final int id;
    late final String title;
    late final String body;

    if (hour >= 18) {
      window = 'evening'; id = _idWorkoutEvening;
      title = '🔥 วันนี้ยังไม่มีการออกกำลังกายบันทึกไว้เลย';
      body  = 'ยังพอมีเวลา ลองขยับร่างกายสักหน่อยก่อนจบวัน';
    } else if (hour >= 12) {
      window = 'afternoon'; id = _idWorkoutAfternoon;
      title = '💪 วันนี้ยังไม่ได้ออกกำลังกายเลย';
      body  = 'ลองแบ่งเวลาสัก 20-30 นาทีดูนะ';
    } else {
      return; // เช้าเกินไป ยังไม่ต้องเร่ง
    }

    final flag = 'workout_$window';
    if (fired.contains(flag)) return;

    await _notify(id, 'workout', title, body);
    _markFired(flag);
  }

  Future<void> _notify(int id, String route, String title, String body) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: LocalNotificationService.chSmart,
        title: title,
        body: body,
        payload: {'route': route},
      ),
    );
  }

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Set<String> _readFired() {
    final raw = _storage.read<List>('$_flagsKeyPrefix${_todayStr()}') ?? [];
    return raw.map((e) => e.toString()).toSet();
  }

  void _markFired(String flag) {
    final key = '$_flagsKeyPrefix${_todayStr()}';
    final fired = _readFired()..add(flag);
    _storage.write(key, fired.toList());
  }
}
