import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_storage/get_storage.dart';

import 'api_fault_injector.dart';

class _CacheEntry {
  final Response response;
  final DateTime time;
  _CacheEntry(this.response, this.time);
}

class ApiClient {
  // ============================================================
  // 📌 ทดสอบบนเครื่องจริง (real device) ต้องแก้ IP ตรงนี้ทุกครั้งที่ย้าย Wi-Fi
  //
  //    วิธีหา IP:
  //    1. เปิด PowerShell/CMD บน PC ที่รัน backend → พิมพ์ `ipconfig`
  //    2. หาบรรทัด "Wireless LAN adapter Wi-Fi" → เอาเลข IPv4 Address มาใส่ด้านล่าง
  //    3. มือถือกับ PC ต้องต่อ Wi-Fi วงเดียวกัน
  //
  //    ถ้าเชื่อมไม่ติด (ลอง http://<IP>:8081/api ในเบราว์เซอร์มือถือแล้วไม่ขึ้น):
  //    - เช็คก่อนว่า backend รันอยู่จริง (`go run main.go`) และ Windows Firewall
  //      อนุญาต inbound port 8081 แล้ว
  //    - Wi-Fi บางเครือข่าย (เช่น หอพัก/ที่สาธารณะ) เปิด "client isolation"
  //      บล็อกอุปกรณ์ในวงเดียวกันคุยกันเอง → ต่อ IP จริงไม่ติดแน่นอน
  //      ทางแก้ชั่วคราว: ต่อสาย USB แล้วรัน `adb reverse tcp:8081 tcp:8081`
  //      จากนั้นเปลี่ยนค่าด้านล่างเป็น '127.0.0.1' แทน IP จริง
  //
  //    ไม่อยากแก้โค้ดทุกครั้งที่ IP เปลี่ยน? ใส่ IP ผ่านคำสั่งรันแทนได้:
  //    flutter run --dart-define=DEVICE=real --dart-define=REAL_IP=<IP ปัจจุบันของ PC>
  //    ไม่ใส่ REAL_IP มา = ใช้ค่า default ด้านล่าง
  // ============================================================
  static const _realDeviceIp =
      String.fromEnvironment('REAL_IP', defaultValue: '192.168.1.50');

  // ตัวเลือก: 'emulator' (default) | 'real'
  // กำหนดผ่าน --dart-define=DEVICE=real ตอน run (ดู .vscode/launch.json)
  static const _device = String.fromEnvironment('DEVICE', defaultValue: 'emulator');

  static String get serverUrl {
    if (kIsWeb) return 'http://localhost:8081';           // Chrome
    if (_device == 'real') return 'http://$_realDeviceIp:8081'; // เครื่องจริง
    return 'http://10.0.2.2:8081';                        // Android Emulator
  }

  static String get baseUrl => '$serverUrl/api';

  late Dio dio;
  final storage = GetStorage();

  /// ทดสอบเท่านั้น (integration_test) — สั่ง arm(...) เพื่อจำลอง network พังกลางทาง
  /// ไม่เรียกอะไรเลย = ไม่มีผลกับแอปจริง
  static final ApiFaultInjector faultInjector = ApiFaultInjector();

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      validateStatus: (status) => status != null,
    ));

    // --- Interceptor: จำลอง network fault (ทดสอบเท่านั้น) ต้องอยู่ก่อนตัวอื่นเสมอ
    //     เพื่อ reject request ก่อนที่จะแตะ header/ยิงจริง ---
    dio.interceptors.add(faultInjector.interceptor);

    // --- Interceptor: ใส่ Token อัตโนมัติก่อนส่ง Request ---
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = storage.read('auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        // ถ้า Token หมดอายุ (401) สามารถสั่ง Logout หรือ Refresh Token ตรงนี้ได้
        if (e.response?.statusCode == 401) {
          // logic logout หรือ redirect ไปหน้า login
        }
        return handler.next(e);
      },
    ));
  }

  static String? prefixPath(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    return s.startsWith('http') ? s : (s.startsWith('/') ? '$serverUrl$s' : '$serverUrl/$s');
  }

  // --- GET cache: กันยิงซ้ำเมื่อสลับแท็บ/กลับมาหน้าเดิมในช่วงเวลาสั้นๆ ---
  // key = path (รวม query string) เพราะทุก service เรียก get() ด้วย path ที่ต่อ query ไว้แล้ว
  static final Map<String, _CacheEntry> _cache = {};
  static const Duration _defaultTtl = Duration(seconds: 30);

  /// [forceRefresh] ใช้ตอน pull-to-refresh/กดรีเฟรชเอง เพื่อข้าม cache
  Future<Response> get(String path, {bool forceRefresh = false, Duration? ttl}) async {
    if (!forceRefresh) {
      final cached = _cache[path];
      if (cached != null &&
          DateTime.now().difference(cached.time) < (ttl ?? _defaultTtl)) {
        return cached.response;
      }
    }
    final response = await dio.get(path);
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      _cache[path] = _CacheEntry(response, DateTime.now());
    }
    return response;
  }

  /// เคลียร์ cache ทั้งหมด — เรียกอัตโนมัติหลัง POST/PUT/DELETE (ข้อมูลอาจเปลี่ยน)
  /// และเรียกเองได้ตอน pull-to-refresh เพื่อบังคับโหลดใหม่จริง
  static void clearCache() => _cache.clear();

  Future<Response> post(String path, dynamic data) async {
    final response = await dio.post(path, data: data);
    clearCache();
    return response;
  }

  Future<Response> put(String path, dynamic data) async {
    final response = await dio.put(path, data: data);
    clearCache();
    return response;
  }

  Future<Response> patch(String path, dynamic data) async {
    final response = await dio.patch(path, data: data);
    clearCache();
    return response;
  }

  Future<Response> delete(String path) async {
    final response = await dio.delete(path);
    clearCache();
    return response;
  }
}