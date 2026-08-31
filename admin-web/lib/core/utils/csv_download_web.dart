// ดาวน์โหลดไฟล์ CSV จากฝั่งเบราว์เซอร์ (Flutter Web เท่านั้น — myapp_admin รันเป็นเว็บอย่างเดียว)
// ใช้ package:web (แทน dart:html ที่เลิกใช้แล้ว): สร้าง Blob -> Object URL -> คลิก <a download> ที่ซ่อนไว้
// แล้วเคลียร์ทิ้งทันที ไม่ทิ้ง element ค้างใน DOM

import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

void downloadCsv(String filename, String csvContent) {
  // BOM (U+FEFF) นำหน้าเนื้อหา ให้ Excel เปิดไฟล์แล้วอ่านภาษาไทย (UTF-8) ถูกต้อง
  // ไม่งั้น Excel เดา encoding ผิดแล้วตัวอักษรไทยเพี้ยนเป็นขยะ
  final bom = String.fromCharCode(0xFEFF);
  final bytes = utf8.encode('$bom$csvContent');
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
