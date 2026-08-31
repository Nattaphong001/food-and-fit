import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_storage/get_storage.dart';

class _CacheEntry {
  final Response response;
  final DateTime time;
  _CacheEntry(this.response, this.time);
}

class ApiClient {
  // ============================================================
  // 📌 เปลี่ยน IP ตรงนี้เมื่อ IP Wi-Fi ของเครื่องเปลี่ยน
  //    (ดู ipconfig แล้วเอา IPv4 ของ Wireless LAN มาใส่)
  // ============================================================
  static const _realDeviceIp = '172.24.150.29';

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