#!/usr/bin/env bash
# ใช้วันสอบ/สาธิต — ห้ามรัน `flutter run` (debug) ตอนโชว์กรรมการ
# debug mode ช้ากว่า release ตามธรรมชาติ (ไม่มี dart2js optimize/minify) ไม่ใช่บั๊ก
# แต่ทำให้ดูเหมือนแอปหน่วงทั้งที่ของจริงเร็ว (วัดแล้ว: boot ~1.8s บน release, warm cache)
set -e
cd "$(dirname "$0")/.."
flutter build web --release --no-web-resources-cdn
python3 tool/serve_web.py
