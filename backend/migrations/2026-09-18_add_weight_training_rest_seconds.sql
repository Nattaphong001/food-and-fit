-- 2026-09-18 — เพิ่มคอลัมน์ wtrs_rest_seconds (weight_training_result)
-- เหตุผล: Step 1 ของ Weight Training Smart Auto Calorie เปลี่ยนเป็น Dynamic Base MET (ดู
-- backend/services/calculator.go, CalculateWeightTrainingCalories) ซึ่งต้องรู้เวลาพักรายเซตจริง
-- (< 30 วิ / 30-60 วิ / ≥ 60 วิ) — ระบบเดิมมีแค่เวลารวมทั้งเซสชัน (wtrs_duration) ไม่มีเวลาพักต่อเซต
-- คอลัมน์นี้เปิดทางให้ backend รับค่าจริงต่อเซตได้ มือถือยังไม่ได้แก้ให้ส่งขึ้นมา ณ วันที่เพิ่ม
-- migration นี้ — ทุกแถวจะเป็น NULL จนกว่าจะแก้ (ระบบ fallback ไปใช้ความหนาแน่นเฉลี่ยทั้งเซสชันแทน
-- เมื่อเป็น NULL)
--
-- ⚠️ ก่อนรัน: backup ตารางก่อนเสมอ
--   mysqldump -u root -p food_and_fit_db weight_training_result > backup_weight_training_result_before_rest_seconds_20260918.sql

ALTER TABLE weight_training_result
  ADD COLUMN wtrs_rest_seconds SMALLINT UNSIGNED NULL DEFAULT NULL
  COMMENT 'เวลาพักหลังเซตนี้ (วินาที) ก่อนเริ่มเซตถัดไป - NULL=ไม่ทราบ (แถวเก่า/มือถือยังไม่ส่ง)'
  AFTER wtrs_active_seconds;

-- Rollback:
-- ALTER TABLE weight_training_result DROP COLUMN wtrs_rest_seconds;
