// บริการ: จดจำอีเมล/รหัสผ่านของหน้า Login แอดมิน (เก็บผ่าน flutter_secure_storage — เข้ารหัส
// ต่างจาก token ที่เก็บใน GetStorage ธรรมดา เพราะรหัสผ่านดิบไวต่อความปลอดภัยกว่ามาก)
// COPY logic มาจาก lib/services/remembered_credentials_service.dart ฝั่งแอปมือถือ — ตัดเมธอด
// updatePasswordIfEmailMatches ออกเพราะแอดมินไม่มีหน้าเปลี่ยน/ลืมรหัสผ่าน
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RememberedCredentials {
  final String email;
  final String password;
  const RememberedCredentials(this.email, this.password);
}

class RememberedCredentialsService {
  static const _storage = FlutterSecureStorage();
  static const _emailKey = 'admin_remembered_email';
  static const _passwordKey = 'admin_remembered_password';

  static Future<RememberedCredentials?> load() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (email == null || password == null) return null;
    return RememberedCredentials(email, password);
  }

  // ลบ key เดิมก่อนเขียนใหม่เสมอ — กันค่าเก่าค้าง เหมือนฝั่งมือถือ
  static Future<void> save(String email, String password) async {
    await clear();
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }
}
