#!/usr/bin/env bash
# ============================================================================
# e2e_body_stats_test.sh — 2026-09-05
# ทดสอบ endpoint /member/body-stats และ /member/profile หลังแก้ FIX-HEIGHT-VALIDATION,
# FIX-DOUBLE-WRITE, GUARD-SHORT-INTERVAL-EDIT
#
# ก่อนรัน:
#   1. เปิด XAMPP MySQL (port 3306)
#   2. เปิด backend: cd backend && go run main.go   (port 8081)
#   3. mint token: cd backend && go run ./cmd_mint_test_token   (mb_id=1)
#      แล้วแทนค่าตัวแปร TOKEN ด้านล่างด้วยค่าที่ได้
#
# ⚠️ ทดสอบกับ mb_id=1 ซึ่งเป็นบัญชี demo/seed (ธนภัทร ใจดี, user01@foodandfit.test)
# สคริปต์นี้แก้ไขข้อมูลจริงของบัญชีนี้ระหว่างรัน แล้ว DELETE แถวที่สร้างเพิ่มออกท้ายสคริปต์
# เพื่อคืนสถานะเดิม — ถ้าจะรันกับ mb_id อื่น ต้องมั่นใจว่าเป็นบัญชีทดสอบ ไม่ใช่สมาชิกจริง
# ============================================================================

set -e

BASE="http://localhost:8081/api"
TOKEN="ใส่ token จาก cmd_mint_test_token ตรงนี้"
MYSQL="/c/xampp/mysql/bin/mysql.exe --default-character-set=utf8mb4"
DB="food_and_fit_db"

hr() { echo "============================================================"; }

hr; echo "TC-03a: EditProfile no-op (gender/birth_date เดิม) — คาดหวัง: ไม่มีแถวใหม่ใน member_bmr_history"
curl -s -X PUT "$BASE/member/profile" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"full_name":"ธนภัทร ใจดี","gender":1,"birth_date":"2010-06-15"}'; echo
$MYSQL -uroot "$DB" -e "SELECT mbh_id, mbh_record_date, mbh_bmr FROM member_bmr_history WHERE mb_id=1 ORDER BY mbh_id;"

hr; echo "TC-03b: EditProfile เปลี่ยนอายุจริง (birth_date -> 2009-06-15, อายุ 16->17) — คาดหวัง: มีแถวใหม่ 1 แถว"
curl -s -X PUT "$BASE/member/profile" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"full_name":"ธนภัทร ใจดี","gender":1,"birth_date":"2009-06-15"}'; echo
$MYSQL -uroot "$DB" -e "SELECT mbh_id, mbh_record_date, mbh_bmr FROM member_bmr_history WHERE mb_id=1 ORDER BY mbh_id;"

hr; echo "TC-01: UpdateBodyStats บันทึกครั้งแรกของวัน (weight 58.0 -> 59.0) — คาดหวัง: mbs +1 แถว, mbh อัปเดตแถวเดิมของวันนี้ (ไม่ใช่ +1)"
curl -s -X PUT "$BASE/member/body-stats" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"weight":59.0,"height":168,"activity_level":1.55,"target":2}'; echo
$MYSQL -uroot "$DB" -e "SELECT mbs_id, mbs_weight, mbs_recorded_date FROM member_body_stats WHERE mb_id=1 ORDER BY mbs_id;"
$MYSQL -uroot "$DB" -e "SELECT mbh_id, mbs_id, mbh_record_date, mbh_bmi, mbh_bmr FROM member_bmr_history WHERE mb_id=1 ORDER BY mbh_id;"

hr; echo "TC-02: บันทึกซ้ำวันเดียวกัน 3 ครั้งติด น้ำหนักต่างกันทุกครั้ง — คาดหวัง: ยังมีแค่ 1 แถวของวันนี้ ค่าสุดท้าย=60.0"
for W in 59.3 59.6 60.0; do
  curl -s -X PUT "$BASE/member/body-stats" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"weight\":$W,\"height\":168,\"activity_level\":1.55,\"target\":2}"; echo
done
$MYSQL -uroot "$DB" -e "SELECT mbs_id, mbs_weight FROM member_body_stats WHERE mb_id=1 ORDER BY mbs_id;"
$MYSQL -uroot "$DB" -e "SELECT mbh_id, mbh_bmi, mbh_bmr FROM member_bmr_history WHERE mb_id=1 ORDER BY mbh_id;"

hr; echo "TC-04a: height=1 (ต่ำกว่าขั้นต่ำ) — คาดหวัง: 400 Bad Request"
curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X PUT "$BASE/member/body-stats" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"weight":60,"height":1,"activity_level":1.55,"target":2}'

hr; echo "TC-04b: height=999 (สูงกว่าขั้นสูงสุด) — คาดหวัง: 400 Bad Request"
curl -s -w "\nHTTP_STATUS:%{http_code}\n" -X PUT "$BASE/member/body-stats" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"weight":60,"height":999,"activity_level":1.55,"target":2}'

hr; echo "TC-05a: น้ำหนักเปลี่ยน +3.5 กก. — คาดหวัง: บันทึกสำเร็จ + warnings ไม่ว่าง"
curl -s -X PUT "$BASE/member/body-stats" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"weight":63.5,"height":168,"activity_level":1.55,"target":2}'; echo

hr; echo "TC-05b: ส่วนสูงเปลี่ยน +2 ซม. — คาดหวัง: บันทึกสำเร็จ + warnings ไม่ว่าง"
curl -s -X PUT "$BASE/member/body-stats" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"weight":63.5,"height":170,"activity_level":1.55,"target":2}'; echo

hr; echo "TC-06: target=1 (ลดน้ำหนัก) + activity=1.2 — คาดหวัง: target_cal ถูก clamp เท่ากับ BMR"
curl -s -X PUT "$BASE/member/body-stats" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"weight":63.5,"height":170,"activity_level":1.2,"target":1}'; echo

hr; echo "TC-07: UpdateBodyStats แบบรวม gender/birth_date ในคำขอเดียว (คืนค่าอายุ 17->16) — คาดหวัง: member_profile อัปเดต, mbh ยังมีแค่แถวเดียวของวันนี้"
curl -s -X PUT "$BASE/member/body-stats" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"weight":63.5,"height":170,"activity_level":1.375,"target":3,"gender":1,"birth_date":"2010-06-15"}'; echo
$MYSQL -uroot "$DB" -e "SELECT mb_id, mb_gender, mb_birth_date FROM member_profile WHERE mb_id=1;"
$MYSQL -uroot "$DB" -e "SELECT mbh_id FROM member_bmr_history WHERE mb_id=1 ORDER BY mbh_id;"

hr; echo "CLEANUP: ลบแถวที่สร้างขึ้นระหว่างเทสต์วันนี้ คืนค่า mb_id=1 กลับสถานะเดิมก่อนรัน"
echo "!! ต้องเช็ค mbs_id/mbh_id ของวันนี้เองก่อนลบ (เปลี่ยนตามรันจริงแต่ละครั้ง) — ตัวอย่างที่ใช้จริงตอนพัฒนา: mbs_id=73, mbh_id=85"
# $MYSQL -uroot "$DB" -e "DELETE FROM member_bmr_history WHERE mbh_id=<ใส่ id ของวันนี้>; DELETE FROM member_body_stats WHERE mbs_id=<ใส่ id ของวันนี้>;"
