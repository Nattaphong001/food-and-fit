import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_storage/get_storage.dart';

import 'auth_service.dart';
import 'lan_scanner.dart';

// endpoint ที่ตอบ 401 ได้เองตามปกติ (ยังไม่ login/ไม่มี token) — ห้ามให้ onResponse ข้างล่าง
// ตีความว่า "session หมดอายุ" แล้วเด้งออกจากหน้า login/สมัครสมาชิกไปซ้ำ
const _authEndpoints = {
  '/login', '/register', '/verify-email', '/resend-otp',
  '/password/forgot', '/password/reset',
};

class _CacheEntry {
  final Response response;
  final DateTime time;
  _CacheEntry(this.response, this.time);
}

class ApiClient {
  static const _port = 8081;
  static const _storageKeyIp = 'api_client_detected_real_device_ip';

  // ตัวเลือก: 'emulator' (default) | 'real'
  // กำหนดผ่าน --dart-define=DEVICE=real ตอน run (ดู .vscode/launch.json)
  static const _device = String.fromEnvironment('DEVICE', defaultValue: 'emulator');

  // ใช้เฉพาะตอน autoDetectServer() หา backend เองไม่เจอจริงๆ (ไม่มี Wi-Fi/ไฟร์วอลล์บล็อก
  // ทั้งวง client isolation) — ไม่ใช่ทางหลักแล้ว ไม่ต้องแก้เลขนี้เวลาเปลี่ยน Wi-Fi
  static const _fallbackIp =
      String.fromEnvironment('REAL_IP', defaultValue: '172.24.149.87');

  // ผลลัพธ์จาก autoDetectServer() — cache ไว้ในหน่วยความจำระหว่างรันแอปครั้งนี้
  static String? _detectedIp;

  static String get serverUrl {
    if (kIsWeb) return 'http://localhost:$_port';                    // Chrome
    // Windows desktop รัน backend บนเครื่องเดียวกัน — 10.0.2.2 ใช้ได้เฉพาะใน Android Emulator
    if (defaultTargetPlatform == TargetPlatform.windows) return 'http://localhost:$_port';
    if (_device == 'real') return 'http://${_detectedIp ?? _fallbackIp}:$_port'; // เครื่องจริง
    return 'http://10.0.2.2:$_port';                                 // Android Emulator
  }

  static String get baseUrl => '$serverUrl/api';

  /// เรียกครั้งเดียวใน main() ก่อน runApp (ก่อนสร้าง ApiClient() ตัวแรก) — หา IP เครื่องที่รัน
  /// backend เองอัตโนมัติ แก้ปัญหาเดิมที่ต้องแก้ค่าคงที่ในไฟล์นี้ทุกครั้งที่ย้าย Wi-Fi/IP เปลี่ยน
  /// (เผลอลืมแก้ = รันแล้วข้อมูลไม่มา เพราะยังชี้ IP เก่าอยู่)
  ///
  /// ลำดับที่ลอง:
  /// 1. IP ที่เคย detect สำเร็จล่าสุด (persist ใน GetStorage) — เร็วสุด ผ่านเกือบทุกครั้งที่ Wi-Fi ไม่เปลี่ยน
  /// 2. สแกน subnet /24 ของวง Wi-Fi ที่เครื่องต่ออยู่ตอนนี้ หา backend จาก GET /api/health
  /// 3. หาไม่เจอทั้งคู่ (ไม่มี Wi-Fi, client isolation บล็อก, ไฟร์วอลล์ปิด port) → fallback ไปใช้
  ///    _fallbackIp เหมือนพฤติกรรมเดิม (ยังแก้ผ่าน --dart-define=REAL_IP=... ได้เหมือนเดิมถ้าจำเป็น)
  static Future<void> autoDetectServer() async {
    if (kIsWeb || _device != 'real') return; // Chrome/Emulator ใช้ IP คงที่อยู่แล้ว ไม่ต้อง detect

    final storage = GetStorage();
    final cachedIp = storage.read<String>(_storageKeyIp);
    debugPrint('[ApiClient] cached IP (จากรันครั้งก่อน, persist ใน GetStorage): $cachedIp');
    if (cachedIp != null && await _probe(cachedIp)) {
      debugPrint('[ApiClient] cached IP ใช้ได้ → ใช้ $cachedIp (ไม่สแกนใหม่)');
      _detectedIp = cachedIp;
      return;
    }
    if (cachedIp != null) debugPrint('[ApiClient] cached IP ใช้ไม่ได้แล้ว (probe fail) → สแกน subnet ใหม่');

    final found = await _scanForBackend();
    if (found != null) {
      debugPrint('[ApiClient] สแกนเจอ backend ที่ $found → บันทึกแทน cache เดิม');
      _detectedIp = found;
      await storage.write(_storageKeyIp, found);
    } else {
      debugPrint('[ApiClient] สแกนไม่เจอ backend เลยทั้ง subnet → ใช้ fallback IP: $_fallbackIp');
    }
    // หาไม่เจอ — ปล่อยให้ serverUrl fallback ไปใช้ _fallbackIp ต่อ (หน้าจอจะขึ้น error state
    // ตามปกติถ้ายังต่อไม่ติด ไม่ต่างจากพฤติกรรมเดิม)
  }

  static final Dio _probeDio = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: 350),
    receiveTimeout: const Duration(milliseconds: 350),
  ));

  /// เช็ค statusCode==200 อย่างเดียวเดิม ใครก็ตอบ 200 บน port 8081 ในวง LAN เดียวกันก็ผ่านได้
  /// (เช่น WiFi หอพัก/สาธารณะที่มีคนอื่นรัน service อื่นบน port เดียวกันโดยบังเอิญ) เพิ่มเช็ค field
  /// "service" ที่ backend ใส่มาด้วย — กันการเชื่อมต่อผิดพลาด/บังเอิญ ไม่ใช่ auth จริงจัง (ค่านี้อยู่ใน
  /// public repo คนตั้งใจปลอมเจาะจงแอปนี้ยังทำได้อยู่ดี) ฟีเจอร์นี้ใช้เฉพาะตอน dev
  /// (--dart-define=DEVICE=real) ไม่ได้อยู่ใน production build
  static Future<bool> _probe(String ip) async {
    try {
      final res = await _probeDio.get('http://$ip:$_port/api/health');
      if (res.statusCode != 200) return false;
      final data = res.data;
      if (data is Map && data['data'] is Map) {
        return (data['data'] as Map)['service'] == 'food_and_fit_api';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _scanForBackend() async {
    final prefixes = await localSubnetPrefixes();
    debugPrint('[ApiClient] subnet prefix ที่ตรวจเจอบนเครื่องนี้: $prefixes');
    if (prefixes.isEmpty) {
      debugPrint('[ApiClient] ไม่เจอ subnet prefix เลย — เช็คว่ามือถือต่อ Wi-Fi อยู่จริงไหม');
    }
    for (final prefix in prefixes) {
      final hit = await _scanPrefix(prefix);
      if (hit != null) return hit;
    }
    return null;
  }

  /// สแกน .1-.254 ของ subnet เป็นชุดๆ ละ 64 ตัวพร้อมกัน (timeout สั้นต่อตัวอยู่แล้วจาก _probeDio)
  static Future<String?> _scanPrefix(String prefix) async {
    debugPrint('[ApiClient] เริ่มสแกน $prefix.1-254 หา backend...');
    const batchSize = 64;
    for (var start = 1; start <= 254; start += batchSize) {
      final end = (start + batchSize - 1).clamp(1, 254);
      final candidates = [for (var i = start; i <= end; i++) '$prefix.$i'];
      final results = await Future.wait(
        candidates.map((ip) async => (await _probe(ip)) ? ip : null),
      );
      for (final ip in results) {
        if (ip != null) return ip;
      }
    }
    debugPrint('[ApiClient] สแกน $prefix.1-254 ครบแล้ว ไม่เจอ backend');
    return null;
  }

  late Dio dio;
  static const _secureStorage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

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
    // token ย้ายไปเก็บ flutter_secure_storage แล้ว (เข้ารหัสระดับ OS) — อ่านเป็น async
    // ต้องรอผลก่อนค่อย handler.next() ไม่งั้น request หลุดออกไปแบบไม่มี Authorization header
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _secureStorage.read(key: _tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      // BaseOptions.validateStatus ด้านบนรับทุก status code ที่ไม่ใช่ null ว่า "สำเร็จ" เสมอ
      // (โค้ด service เดิมทั้งหมด เช็ค response.statusCode เองแบบ manual ไม่ throw) เพราะงั้น 401
      // จะไม่มีวันโผล่มาที่ onError นี้เลย ต้องดักที่ onResponse แทนถึงจะเจอจริง
      onResponse: (response, handler) {
        if (response.statusCode == 401 && !_authEndpoints.contains(response.requestOptions.path)) {
          AuthService.to.handleUnauthorized();
        }
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        // ทางนี้เจอเฉพาะ error ระดับ connection จริงๆ (timeout, ไม่มีเน็ต, DNS ไม่เจอ ฯลฯ)
        // ไม่ใช่ 401/4xx/5xx — ของพวกนั้นดักที่ onResponse ด้านบนแล้ว
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