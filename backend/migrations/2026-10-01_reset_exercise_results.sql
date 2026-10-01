-- 2026-10-01 — ล้างผลการออกกำลังกายของสมาชิกทั้งหมด (เวทเทรนนิ่ง + คาร์ดิโอ) และรีเซ็ตเลข id กลับไปเริ่ม 1
--
-- เหตุผล: เปลี่ยนสูตรพลังงานเวทเทรนนิ่งเป็น Dynamic METs รายเซตตาม %1RM (2026-10-01, ดู
-- 2026-10-01_drop_wet_mets.sql และ ../../CLAUDE.md ข้อ 7[B-1]) wtrs_calories เดิมคำนวณด้วยโมเดลเก่า
-- หลายรุ่นปนกัน (Session MET + RIR, METs คงที่ต่อท่า) เทียบกันไม่ได้ ผู้ใช้ตัดสินใจล้างข้อมูลผลการ
-- ออกกำลังกายทิ้งทั้งหมดแทนการ backfill ให้ข้อมูลทั้งระบบมาจากสูตรเดียวกัน — cardio_result ล้างด้วย
-- (สูตรคาร์ดิโอไม่เปลี่ยน) เพื่อให้ข้อมูลการออกกำลังกายเริ่มต้นชุดเดียวกัน
--
-- ไม่แตะ: workout_schedules (แผนฝึก), member_*, daily_nutrition, master data ทั้งหมด
-- ไม่มีตารางไหนมี FK ชี้เข้า weight_training_result / cardio_result (ตรวจ schema.sql แล้ว) จึง TRUNCATE ได้
-- TRUNCATE รีเซ็ต AUTO_INCREMENT ให้อัตโนมัติ
--
-- ⚠️ TRUNCATE เป็น DDL ย้อนด้วย ROLLBACK ไม่ได้ — ต้อง backup ก่อนรันทุกครั้ง:
--   mysqldump -u root food_and_fit_db weight_training_result cardio_result > backups/backup_exercise_results_before_reset_20261001.sql

TRUNCATE TABLE weight_training_result;
TRUNCATE TABLE cardio_result;

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-10-01_reset_exercise_results.sql',
   'ล้าง weight_training_result + cardio_result และรีเซ็ต id หลังเปลี่ยนสูตรพลังงานเวทเป็น Dynamic METs ตาม %1RM');

-- ตรวจหลังรัน (ต้องได้ 0 ทั้งคู่ และ AUTO_INCREMENT = 1):
--   SELECT COUNT(*) FROM weight_training_result;
--   SELECT COUNT(*) FROM cardio_result;
--   SELECT TABLE_NAME, AUTO_INCREMENT FROM information_schema.TABLES
--   WHERE TABLE_SCHEMA = 'food_and_fit_db' AND TABLE_NAME IN ('weight_training_result', 'cardio_result');

-- Rollback (restore จากไฟล์ backup):
--   mysql -u root food_and_fit_db < backups/backup_exercise_results_before_reset_20261001.sql
--   DELETE FROM schema_migrations WHERE filename = '2026-10-01_reset_exercise_results.sql';
