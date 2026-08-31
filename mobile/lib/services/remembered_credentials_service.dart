// บริการ: จดจำอีเมล/รหัสผ่านของหน้า Login (เก็บผ่าน flutter_secure_storage — เข้ารหัส
// ระดับ OS ต่างจาก token ที่เก็บใน GetStorage ธรรมดา เพราะรหัสผ่านดิบไวต่อความปลอดภัยกว่ามาก)
// รวมไว้ที่เดียวเพราะมีหลายจุดต้องแตะค่านี้: LoginView (โหลด/บันทึก/ล้าง),
// ChangePasswordView + ForgotPasswordView (ต้องอัปเดตรหัสที่จำไว้เมื่อรหัสผ่านจริงเปลี่ยน
// ไม่งั้นรหัสที่จำไว้ค้างเป็นค่าเก่า auto-fill แล้ว login ไม่ผ่าน)
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RememberedCredentials {
  final String email;
  final String password;
  const RememberedCredentials(this.email, this.password);
}

class RememberedCredentialsService {
  static const _storage = FlutterSecureStorage();
  static const _emailKey = 'remembered_email';
  static const _passwordKey = 'remembered_password';

  static Future<RememberedCredentials?> load() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    if (email == null || password == null) return null;
    return RememberedCredentials(email, password);
  }

  // ลบ key เดิมก่อนเขียนใหม่เสมอ — flutter_secure_storage บน Android บางเครื่อง write()
  // ทับค่าเดิมของ key เดียวกันไม่ติด (ค้างค่าบัญชี/รหัสเก่า) ต้อง delete() ก่อนเสมอถึงจะชัวร์
  static Future<void> save(String email, String password) async {
    await clear();
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
  }

  // เรียกหลังเปลี่ยน/รีเซ็ตรหัสผ่านสำเร็จ — ถ้าอีเมลที่เพิ่งเปลี่ยนรหัสตรงกับอีเมลที่จำไว้
  // อยู่ อัปเดตรหัสที่จำไว้ให้เป็นรหัสใหม่ทันที กันค้างรหัสเก่าไว้จนล็อกอินครั้งต่อไปพัง
  static Future<void> updatePasswordIfEmailMatches(String email, String newPassword) async {
    final current = await load();
    if (current != null && current.email.trim().toLowerCase() == email.trim().toLowerCase()) {
      await save(current.email, newPassword);
    }
  }
}
