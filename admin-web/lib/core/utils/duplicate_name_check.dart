import 'package:dio/dio.dart';
import '../../services/api_client.dart';

// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] checkExactNameDuplicate
// [DESCRIPTION] เช็คชื่อซ้ำแบบครอบทั้งระบบผ่าน endpoint ค้นหาที่มีอยู่แล้ว (ไม่สร้าง endpoint ใหม่)
//               — ยิง search แบบ LIKE ไปก่อนแล้วกรองเทียบ exact match (case-insensitive, trim)
//               เองฝั่ง Dart เพราะ endpoint ไม่มี exact-match param ให้ ใช้แทนการเช็คใน list ที่
//               โหลดมาแค่หน้าปัจจุบัน (ไม่ครอบทั้งระบบอีกต่อไปตั้งแต่ server-side pagination)
// [INPUT] api, path (เช่น '/admin/nutrition/foods'), nameField/idField ของ response แต่ละแถว,
//         name ที่พิมพ์, excludeId (id รายการที่กำลังแก้ไข — ไม่นับว่าซ้ำกับตัวเอง), cancelToken
// [OUTPUT] true = เจอชื่อซ้ำเป๊ะ (ไม่ใช่ตัวเอง), false = ไม่ซ้ำ **หรือ** เช็คไม่สำเร็จ (network/server
//          error) — โดยตั้งใจไม่ throw ต่อ ยกเว้นถูกยกเลิก (DioExceptionType.cancel ปล่อยผ่านให้
//          ผู้เรียกจับเอง จะได้รู้ว่าไม่ต้องอัปเดต UI) เพราะห้าม block การบันทึกถ้าเช็คซ้ำล้มเหลว
//          (ปล่อยให้ unique constraint ฝั่ง backend เป็นด่านสุดท้ายแทน)
// [RELATED] COMMON_UI
// --------------------------------------------
Future<bool> checkExactNameDuplicate({
  required ApiClient api,
  required String path,
  required String nameField,
  required String idField,
  required String name,
  dynamic excludeId,
  required CancelToken cancelToken,
}) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;

  final query = 'search=${Uri.encodeQueryComponent(trimmed)}&page=1&page_size=100';
  try {
    final res = await api.get('$path?$query', cancelToken: cancelToken);
    if (res.statusCode != 200) return false;
    final data = res.data as Map;
    final list = (data['data'] ?? []) as List;
    final target = trimmed.toLowerCase();
    return list.any((item) {
      final itemName = (item[nameField] ?? '').toString().trim().toLowerCase();
      if (itemName != target) return false;
      if (excludeId != null && item[idField] == excludeId) return false;
      return true;
    });
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) rethrow;
    return false;
  } catch (_) {
    return false;
  }
}
