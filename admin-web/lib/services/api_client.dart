import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_storage/get_storage.dart';
import '../core/constants/api_config.dart';
import '../views/login_view.dart';
import 'admin_auth_service.dart';

class _CacheEntry {
  final Response response;
  final DateTime time;
  _CacheEntry(this.response, this.time);
}

// เดิม (โปรเจกต์มือถือ) เลือก base URL ตาม kIsWeb / DEVICE (emulator, real device IP)
// เพราะ 1 โค้ดรันได้ทั้ง Android/iOS/Web — โปรเจกต์นี้เป็นเว็บ Admin อย่างเดียว
// จึงตัด logic เลือก IP ตาม platform ออก เหลือแค่ ApiConfig.baseUrl (ตั้งผ่าน --dart-define)
class ApiClient {
  static String get serverUrl => ApiConfig.baseUrl;
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
      // --------------------------------------------
      // [FEATURE] AUTH
      // [FUNCTION] ApiClient (onResponse interceptor — auto-logout on 401)
      // [DESCRIPTION] BaseOptions.validateStatus ด้านบนตั้งไว้ว่า status ใดๆ ที่ไม่ใช่ null ถือว่า
      //               "สำเร็จ" (ไม่ throw) เพื่อให้ทุกหน้าเช็ค response.statusCode เองได้ตามเดิม
      //               (pattern เดิมทั้งระบบ) — 401 จึงไม่มีทางเข้า onError เลย (ไม่ throw
      //               DioException) ต้องดัก "logout อัตโนมัติเมื่อ token หมดอายุ" ที่ onResponse
      //               แทน ไม่ใช่ onError ถึงจะทำงานได้จริง — เดิมเป็น onError ว่างเปล่าไม่เคยทำงาน
      //               ยกเว้น path '/login' เอง: 401 จากตรงนั้นคือ "รหัสผ่าน/อีเมลผิด" ตอนล็อกอิน
      //               (พฤติกรรมปกติของฟอร์ม ไม่ใช่ session หมดอายุ) ถ้าไม่ยกเว้น จะ Get.offAll ทับ
      //               LoginView เดิมกลางคันตอนกด login พลาด ทำให้ฟอร์มโดนรีเซ็ต (เคยแก้ไม่ได้/
      //               ข้อความ error ที่ควรโชว์หาย เพราะ _submit() เช็ค mounted แล้วเจอ false)
      // [INPUT] response ของทุก request ที่ผ่าน ApiClient
      // [OUTPUT] response.statusCode == 401 (path อื่นที่ไม่ใช่ /login) → logout() + redirect ไป
      //          LoginView ทั้งเว็บ (ไม่ใช่แค่หน้าที่ยิง request) response อื่นผ่านต่อไปยังโค้ดเดิมตามปกติ
      // [RELATED] AUTH
      // --------------------------------------------
      onResponse: (response, handler) {
        final isLoginRequest = response.requestOptions.path == '/login';
        if (response.statusCode == 401 && !isLoginRequest) {
          AdminAuthService.to.logout();
          Get.offAll(() => const LoginView());
        }
        return handler.next(response);
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
  /// [cancelToken] ใช้กับหน้าที่ยิง GET ซ้ำเร็วๆ ตามตัวกรอง/pagination (debounce ค้นหา, เปลี่ยนหน้า)
  /// — ยกเลิก request เก่าที่ยังไม่ตอบกลับก่อนยิงใหม่ กัน response เก่ามาทีหลังทับผลลัพธ์ใหม่
  Future<Response> get(String path, {bool forceRefresh = false, Duration? ttl, CancelToken? cancelToken}) async {
    if (!forceRefresh) {
      final cached = _cache[path];
      if (cached != null &&
          DateTime.now().difference(cached.time) < (ttl ?? _defaultTtl)) {
        return cached.response;
      }
    }
    final response = await dio.get(path, cancelToken: cancelToken);
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
