// ══════════════════════════════════════════════
// [FEATURE] COMMON_UI
// [FUNCTION] ApiFaultInjector
// [DESCRIPTION] ทดสอบเท่านั้น — จำลอง network error กลางทาง (ตัดเน็ต/พังบางรายการ)
//               ให้ integration_test เรียก ApiClient.faultInjector.arm(...) ก่อนเริ่ม flow
//               ปกติ (ไม่เรียก arm) จะไม่มีผลอะไรกับแอปจริงเลย
// [INPUT] ApiFaultRule (matcher ของ request + จะพังตอนครั้งที่เท่าไหร่)
// [OUTPUT] Dio Interceptor ที่ reject request เป็น DioExceptionType.connectionError
// [RELATED] api_client.dart
// --------------------------------------------
import 'package:dio/dio.dart';

class ApiFaultRule {
  /// คืน true ถ้า request นี้ตรงกับเงื่อนไขที่จะจับ (เช่น เช็ค path/method)
  final bool Function(RequestOptions options) matcher;

  /// พังตอนที่ request ที่ตรง matcher ถูกยิงเป็นครั้งที่เท่าไหร่ (1 = ครั้งแรกเลย)
  final int failAtCall;

  /// true = พังครั้งเดียวแล้วปลด rule ทิ้ง (ใช้จำลอง "พังกลางทาง" แล้วครั้งต่อไปสำเร็จ)
  final bool once;

  int callCount = 0;

  ApiFaultRule({
    required this.matcher,
    required this.failAtCall,
    this.once = true,
  });

  /// helper ใช้บ่อย: match ตาม path (contains) + method (ถ้าระบุ)
  static ApiFaultRule byPath(
    String pathContains, {
    required int failAtCall,
    String? method,
    bool once = true,
  }) {
    return ApiFaultRule(
      matcher: (options) {
        final pathMatch = options.path.contains(pathContains);
        final methodMatch = method == null || options.method.toUpperCase() == method.toUpperCase();
        return pathMatch && methodMatch;
      },
      failAtCall: failAtCall,
      once: once,
    );
  }
}

class ApiFaultInjector {
  final List<ApiFaultRule> _rules = [];

  void arm(ApiFaultRule rule) => _rules.add(rule);

  /// เคลียร์ทุก rule — เรียกใน tearDown ของแต่ละเทสต์เสมอ กัน rule เก่าหลุดไปเทสต์ถัดไป
  void clear() => _rules.clear();

  Interceptor get interceptor => InterceptorsWrapper(
        onRequest: (options, handler) {
          for (final rule in List<ApiFaultRule>.from(_rules)) {
            if (!rule.matcher(options)) continue;
            rule.callCount++;
            if (rule.callCount == rule.failAtCall) {
              if (rule.once) _rules.remove(rule);
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                  error: 'Simulated network failure (integration_test)',
                ),
              );
              return;
            }
          }
          handler.next(options);
        },
      );
}
