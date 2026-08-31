import 'package:dio/dio.dart';

// --------------------------------------------
// [FEATURE] COMMON_UI
// [FUNCTION] isNetworkDioError
// [DESCRIPTION] แยก error จาก DioException ว่าเป็น "เชื่อมต่อไม่ได้" (ไม่มีเน็ต/timeout) หรือ
//               "server ตอบ error" (เช่น 4xx/5xx ที่ต่อเน็ตได้ปกติ) — ใช้เลือกข้อความ error
//               คนละแบบให้ผู้ใช้ ตามมาตรฐานตัวกรอง ข้อ 4 (แยก network fail กับ server error)
// [INPUT] DioException
// [OUTPUT] bool — true = เชื่อมต่อไม่ได้ (ไม่มีเน็ต/timeout), false = กรณีอื่น (เช่น server ตอบ error)
// [RELATED] COMMON_UI
// --------------------------------------------
bool isNetworkDioError(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return true;
    default:
      return false;
  }
}
