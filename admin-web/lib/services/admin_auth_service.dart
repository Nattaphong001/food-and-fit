// หน้า: Admin Auth Service (เว็บ)
// ทำหน้าที่: login/logout ของแอดมิน + role guard — เขียนใหม่เฉพาะโปรเจกต์เว็บนี้
// ไม่ได้ copy จาก lib/services/auth_service.dart ของแอปมือถือตรงๆ เพราะไฟล์นั้นผูกกับ
// เรื่องที่ไม่เกี่ยวกับ Admin เลย (local notification, remembered credentials, เช็ค
// profile ร่างกายของสมาชิก) — เอาเฉพาะ endpoint/logic ส่วนที่ Admin ใช้จริงมาตัดสร้างใหม่
//
// endpoint ที่เรียก (ตรวจสอบจริงจาก routes/api.go + auth_controller.go ฝั่ง backend แล้ว):
//   POST /api/login          — endpoint เดียวกับที่แอปมือถือใช้ล็อกอินทั้งสมาชิกและแอดมิน
//                               เช็ค member_profile ก่อน ไม่เจอค่อยเช็ค system_data (แอดมิน)
//                               คืน {role: 'admin' | 'member', token, user}
//   POST /api/admin/logout   — revoke token (ต้องมี Bearer token แอดมินที่ valid)
//   GET  /api/admin/analytics/overview — ใช้ validate session ตอนเปิดเว็บ/refresh ว่า
//                               token ที่ค้างอยู่ใน storage ยัง valid + เป็นแอดมินจริงไหม
//
// role guard: /api/login คืน token ให้ทุก role ที่รหัสผ่านถูก (ไม่ได้เช็คว่าเป็นแอดมินก่อนออก
// token) — ถ้า role ที่ได้กลับมาไม่ใช่ 'admin' ต้อง "ไม่เก็บ token นั้นไว้เลย" ไม่ใช่เก็บแล้วค่อยเคลียร์
// ทีหลัง กันกรณีมี error ระหว่างทางแล้ว token ของสมาชิกค้างอยู่ใน storage ของเว็บแอดมิน

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'api_client.dart';

class AdminAuthService extends GetxService {
  static AdminAuthService get to => Get.find();

  final ApiClient _api = ApiClient();
  final _storage = GetStorage();

  static const String _tokenKey = 'auth_token';
  static const String _userDataKey = 'user_data';

  final isLoggedIn = false.obs;
  final isLoading = false.obs;
  final isCheckingSession = true.obs;
  final adminName = ''.obs;
  final adminEmail = ''.obs;

  @override
  void onInit() {
    super.onInit();
    checkLoginStatus();
  }

  Future<void> checkLoginStatus() async {
    final token = _storage.read<String>(_tokenKey);
    if (token == null) {
      isCheckingSession.value = false;
      return;
    }
    final userData = _storage.read(_userDataKey);
    if (userData is Map) {
      adminName.value = userData['full_name']?.toString() ?? '';
      adminEmail.value = userData['email']?.toString() ?? '';
    }
    // มี token ค้างอยู่ — ต้อง validate กับ server ก่อน ว่ายังไม่หมดอายุ/ไม่ถูก revoke
    try {
      final res = await _api.get('/admin/analytics/overview', forceRefresh: true);
      if (res.statusCode == 200) {
        isLoggedIn.value = true;
      } else {
        await _clearSession();
      }
    } catch (_) {
      // เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — ปล่อยให้ยัง login ค้างไว้ก่อน (เหมือนฝั่งมือถือ)
      isLoggedIn.value = true;
    } finally {
      isCheckingSession.value = false;
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      isLoading.value = true;
      final response = await _api.post('/login', {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        final role = data['role'] ?? '';
        final token = data['token'];

        if (role != 'admin') {
          // ล็อกอินสำเร็จแต่ไม่ใช่แอดมิน (เช่น กรอกบัญชีสมาชิกทั่วไป) — ห้ามเก็บ token นี้ไว้เด็ดขาด
          return {
            'success': false,
            'message': 'บัญชีนี้ไม่ใช่บัญชีแอดมิน ไม่สามารถเข้าใช้งานหน้านี้ได้',
          };
        }

        if (token == null) {
          return {'success': false, 'message': 'เข้าสู่ระบบไม่สำเร็จ (ไม่พบ token)'};
        }

        final userData = data['user'];
        await _storage.write(_tokenKey, token);
        await _storage.write(_userDataKey, userData);

        if (userData is Map) {
          adminName.value = userData['full_name']?.toString() ?? '';
          adminEmail.value = userData['email']?.toString() ?? '';
        }
        isLoggedIn.value = true;
        return {'success': true, 'message': data['message'] ?? 'เข้าสู่ระบบสำเร็จ'};
      }

      final msg = response.data is Map
          ? (response.data['error'] ?? response.data['message'] ?? 'อีเมลหรือรหัสผ่านไม่ถูกต้อง')
          : 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
      return {'success': false, 'message': msg};
    } catch (e) {
      return {'success': false, 'message': 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    try {
      await _api.post('/admin/logout', {});
    } catch (_) {
      // network error — ยัง logout ฝั่งเครื่องได้เสมอ
    }
    await _clearSession();
  }

  Future<void> _clearSession() async {
    await _storage.remove(_tokenKey);
    await _storage.remove(_userDataKey);
    isLoggedIn.value = false;
    adminName.value = '';
    adminEmail.value = '';
  }
}
