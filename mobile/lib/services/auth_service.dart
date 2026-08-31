import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'api_client.dart';
import 'local_notification_service.dart';
import 'notification_service.dart';
import 'remembered_credentials_service.dart';

class AuthService extends GetxService {
  // ทำให้เรียกใช้ง่ายๆ ผ่าน AuthService.to
  static AuthService get to => Get.find();

  final ApiClient _api = ApiClient();
  final _storage = GetStorage();

  // Keys สำหรับเก็บข้อมูล
  static const String _tokenKey = 'auth_token';
  static const String _roleKey = 'user_role';
  static const String _userDataKey = 'user_data';
  static const String _profileCompleteKey = 'is_profile_complete';
  static const String _installMarkerKey = 'app_install_marker';

  // Observable variables สำหรับ UI
  final isLoggedIn = false.obs;
  final isLoading = false.obs;
  final userRole = ''.obs; // 'admin' หรือ 'user'
  final isProfileComplete = false.obs; // ✅ เช็คว่ากรอกข้อมูลร่างกายหรือยัง

  @override
  void onInit() {
    super.onInit();
    // เช็คสถานะตอนเปิดแอป
    _clearRememberedCredentialsOnFreshInstall();
    checkLoginStatus();
  }

  // iOS Keychain ไม่ถูกลบตอนถอนแอป (ต่างจาก GetStorage ที่เก็บในโฟลเดอร์แอปแล้วถูกลบไปด้วย)
  // ถ้าไม่เจอ marker นี้ (เพิ่งติดตั้งใหม่ หรือเคยลบข้อมูลแอป) ต้องล้างรหัสผ่านที่จำไว้เก่าทิ้ง
  // กันโชว์บัญชี/รหัสผ่านเก่าที่ค้างข้ามการติดตั้งโดยไม่ได้ตั้งใจ
  Future<void> _clearRememberedCredentialsOnFreshInstall() async {
    if (_storage.read(_installMarkerKey) != true) {
      await RememberedCredentialsService.clear();
      await _storage.write(_installMarkerKey, true);
    }
  }

  void checkLoginStatus() {
    final token = _storage.read(_tokenKey);
    final role = _storage.read(_roleKey);
    final profileStatus = _storage.read(_profileCompleteKey) ?? false;

    if (token != null) {
      isLoggedIn.value = true;
      userRole.value = role ?? '';
      isProfileComplete.value = profileStatus;
      // Validate token against server in background — clears session if expired
      _validateToken();
    }
  }

  Future<void> _validateToken() async {
    final tokenAtStart = _storage.read<String>(_tokenKey);
    try {
      final response = await _api.get('/member/profile');
      // ถ้า token เปลี่ยนระหว่างรอ = มี login ใหม่เข้ามา ไม่ต้อง clear
      final tokenNow = _storage.read<String>(_tokenKey);
      if (response.statusCode == 401 && tokenAtStart == tokenNow) {
        await _clearSession();
      }
    } catch (_) {
      // Network error — keep session alive so app works offline
    }
  }

  Future<void> _eraseUserData() async {
    // ลบทีละ key แทน erase() เพื่อความปลอดภัย
    for (final key in [
      _tokenKey, _roleKey, _userDataKey, _profileCompleteKey,
      // workout plan keys
      'active_plan_id', 'active_plan_days', 'active_plan_name',
      'active_plan_type', 'active_plan_weekday_based',
      'custom_plan_id', 'custom_plan_name',
      // user_plan slots 2-7
      for (int d = 2; d <= 7; d++) ...['user_plan_$d', 'user_plan_name_$d'],
      // notification
      'workout_notif_date',
    ]) {
      _storage.remove(key);
    }
    NotificationService.to.clearAll();
    await LocalNotificationService.to.cancelAll();
  }

  Future<void> _clearSession() async {
    await _eraseUserData();
    isLoggedIn.value = false;
    isProfileComplete.value = false;
    userRole.value = '';
  }

  // ==========================================
  // 🔓 เข้าสู่ระบบแบบรวม (เช็คฐานข้อมูลจริง)
  // ==========================================
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      isLoading.value = true;
      print('[Login] 1. calling /login...');

      final response = await _api.post('/login', {
        'email': email,
        'password': password,
      });

      print('[Login] 2. status=${response.statusCode}');

      if (response.statusCode == 200) {
        final data = response.data;
        final token = data['token'];
        final role = data['role'] ?? 'user';
        final userData = data['user']; // {id, full_name, email}

        print('[Login] 3. token=${token != null ? "ok" : "null"} role=$role');

        if (token != null) {
          // ล้างข้อมูล user คนก่อนทั้งหมดก่อนบันทึก session ใหม่
          await _eraseUserData();
          print('[Login] 4. eraseUserData done');
          // บันทึก token ก่อน เพื่อให้เรียก API ถัดไปได้
          await _storage.write(_tokenKey, token);
          await _storage.write(_roleKey, role);
          await _storage.write(_userDataKey, userData);

          bool isComplete = false;
          if (role == 'admin') {
            isComplete = true;
          } else {
            // เช็คจาก /member/profile ว่ากรอกข้อมูลร่างกายแล้วหรือยัง
            try {
              final profileRes = await _api.get('/member/profile');
              if (profileRes.statusCode == 200) {
                final stats = profileRes.data['body_stats'] as Map<String, dynamic>?;
                final height = double.tryParse(stats?['height']?.toString() ?? '0') ?? 0;
                final weight = double.tryParse(stats?['weight']?.toString() ?? '0') ?? 0;
                isComplete = height > 0 && weight > 0;
              }
            } catch (_) {
              isComplete = false;
            }
          }

          await _storage.write(_profileCompleteKey, isComplete);
          isLoggedIn.value = true;
          userRole.value = role;
          isProfileComplete.value = isComplete;

          return {
            'success': true,
            'message': data['message'] ?? 'เข้าสู่ระบบสำเร็จ',
            'role': role,
            'data': userData,
            'restored': data['restored'] == true,
          };
        }
      }
      final msg = response.data is Map
          ? (response.data['message'] ?? response.data['error'] ?? 'อีเมลหรือรหัสผ่านไม่ถูกต้อง')
          : 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
      return {'success': false, 'message': msg};
    } catch (e, st) {
      print('[Login] ERROR: $e\n$st');
      return {'success': false, 'message': 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้'};
    } finally {
      isLoading.value = false;
    }
  }

  // ✅ อัปเดตสถานะเมื่อกรอก Onboarding เสร็จ
  void updateProfileStatus(bool status) {
    isProfileComplete.value = status;
    _storage.write(_profileCompleteKey, status);
  }

  // ==========================================
  // 📝 สมัครสมาชิก (Register)
  // ==========================================
  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
    String gender = '',
    String birthDate = '',
  }) async {
    try {
      isLoading.value = true;

      final response = await _api.post('/register', {
        'full_name': fullName,
        'email': email,
        'password': password,
        if (gender.isNotEmpty) 'gender': gender,
        if (birthDate.isNotEmpty) 'birth_date': birthDate,
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': response.data['message'] ?? 'สมัครสมาชิกสำเร็จ กรุณายืนยัน OTP'
        };
      }
      final data = response.data;
      final msg = data is Map ? (data['error'] ?? data['message']) : null;
      return {
        'success': false,
        'message': msg?.toString() ?? 'สมัครสมาชิกไม่สำเร็จ'
      };
    } catch (e) {
      debugPrint('Register Error: $e');
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  // ==========================================
  // ✅ ยืนยัน OTP (Verify Email)
  // ==========================================
  Future<Map<String, dynamic>> verifyOtp(String email, String otp) async {
    try {
      isLoading.value = true;

      final response = await _api.post('/verify-email', {
        'email': email,
        'otp': otp,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        final token = data['token'];
        if (token != null) {
          await _storage.write(_tokenKey, token);
          await _storage.write(_roleKey, 'user');
          if (data['user'] != null) {
            await _storage.write(_userDataKey, data['user']);
          }
          isLoggedIn.value = true;
          userRole.value = 'user';
          isProfileComplete.value = false;
        }
        return {
          'success': true,
          'message': data['message'] ?? 'ยืนยันอีเมลสำเร็จ',
        };
      }
      return {
        'success': false,
        'message': response.data['message'] ?? 'รหัส OTP ไม่ถูกต้อง'
      };
    } catch (e) {
      debugPrint('Verify OTP Error: $e');
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    } finally {
      isLoading.value = false;
    }
  }

  // ==========================================
  // 🔁 ส่งรหัส OTP ใหม่ (Resend OTP)
  // ==========================================
  Future<Map<String, dynamic>> resendOtp(String email) async {
    try {
      final response = await _api.post('/resend-otp', {'email': email});

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': response.data['message'] ?? 'ส่งรหัส OTP ใหม่แล้ว'
        };
      }
      return {
        'success': false,
        'message': response.data['message'] ?? 'ไม่สามารถส่ง OTP ได้'
      };
    } catch (e) {
      debugPrint('Resend OTP Error: $e');
      return {'success': false, 'message': 'เกิดข้อผิดพลาด: $e'};
    }
  }

  // ==========================================
  // 🔐 ร้องขอ OTP รีเซ็ตรหัสผ่าน
  // ==========================================
  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    try {
      final response = await _api.post('/password/forgot', {'email': email});
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'ส่ง OTP ไปที่อีเมลของคุณแล้ว'};
      }
      final data = response.data;
      final msg = data is Map ? (data['error'] ?? data['message']) : null;
      return {'success': false, 'message': msg?.toString() ?? 'ไม่สามารถส่ง OTP ได้'};
    } catch (e) {
      return {'success': false, 'message': 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้'};
    }
  }

  // ==========================================
  // 🔄 รีเซ็ตรหัสผ่าน (Reset Password)
  // ==========================================
  Future<Map<String, dynamic>> resetPassword(String email, String otp, String newPassword) async {
    try {
      isLoading.value = true;
      final response = await _api.post('/password/reset', {
        'email': email,
        'otp_code': otp,
        'new_password': newPassword,
      });

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'เปลี่ยนรหัสผ่านสำเร็จแล้ว'};
      }
      final data = response.data;
      final msg = data is Map ? (data['error'] ?? data['message']) : null;
      return {'success': false, 'message': msg?.toString() ?? 'เปลี่ยนรหัสผ่านไม่สำเร็จ'};
    } catch (e) {
      return {'success': false, 'message': 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้'};
    } finally {
      isLoading.value = false;
    }
  }

  // ==========================================
  // 🔑 เปลี่ยนรหัสผ่าน (Change Password)
  // ==========================================
  Future<Map<String, dynamic>> changePassword(String currentPassword, String newPassword) async {
    try {
      isLoading.value = true;
      final response = await _api.post('/member/password/change', {
        'old_password': currentPassword,
        'new_password': newPassword,
      });
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'เปลี่ยนรหัสผ่านสำเร็จ'};
      }
      final data = response.data;
      final msg = data is Map ? (data['error'] ?? data['message'] ?? 'รหัสผ่านเดิมไม่ถูกต้อง') : 'รหัสผ่านเดิมไม่ถูกต้อง';
      return {'success': false, 'message': msg};
    } catch (e) {
      return {'success': false, 'message': 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้'};
    } finally {
      isLoading.value = false;
    }
  }

  // ==========================================
  // 🚪 ออกจากระบบ (Logout)
  // ==========================================
  Future<void> logout() async {
    try {
      final path = userRole.value == 'admin' ? '/admin/logout' : '/logout';
      await _api.post(path, {});
    } catch (_) {
      // Network error — ยังต้อง logout ฝั่งเครื่องได้เสมอ
    }
    await _clearSession();
    Get.offAllNamed('/login');
  }

  // Helper Methods
  String? getToken() => _storage.read(_tokenKey);
  String? getRole() => _storage.read(_roleKey);
  Map<String, dynamic>? getUserData() => _storage.read(_userDataKey);
  bool get isAdmin => userRole.value == 'admin';
  bool get isUser => userRole.value == 'member';
}