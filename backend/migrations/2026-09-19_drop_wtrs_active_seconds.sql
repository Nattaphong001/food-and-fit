-- 2026-09-19 — ตัดคอลัมน์ wtrs_active_seconds (weight_training_result) ทิ้งถาวร
-- เหตุผล: เวลาออกแรงจริงต่อเซตเป็นค่าที่มือถือจับไว้เฉยๆ ส่งขึ้น API เก็บเป็นหลักฐานย้อนหลัง —
-- services.CalculateWeightTrainingCalories ไม่เคยอ่านค่านี้ (ฐานเวลาของสูตรคือ wtrs_duration =
-- เวลารวมทั้งเซสชัน รวมช่วงพัก) ผู้ใช้ตัดสินใจ 2026-09-19 ให้ตัดสิ่งที่ไม่เกี่ยวกับการคำนวณพลังงานเวทออก
-- ตัดพร้อมโค้ด Go (models/controllers) และฝั่งมือถือ (weight_training_exercise_view.dart หยุดจับ/ส่ง)
--
-- ⚠️ ก่อนรัน: backup ตารางก่อนเสมอ (ทำแล้ว)
--   backups/backup_weight_training_result_before_drop_active_seconds_20260919.sql
--
-- ⚠️ หลังรัน ต้อง restart backend (go run main.go ใหม่) — binary เก่าที่ยังมีฟิลด์นี้จะ INSERT ไม่ผ่าน

ALTER TABLE weight_training_result
  DROP COLUMN wtrs_active_seconds;

-- Rollback (ข้อมูลเดิมกู้คืนได้จาก backup ด้านบนเท่านั้น):
-- ALTER TABLE weight_training_result
--   ADD COLUMN wtrs_active_seconds SMALLINT UNSIGNED NULL
--   COMMENT 'เวลาออกแรงจริงของเซตนี้ (วินาที)'
--   AFTER wtrs_reps;
-- แล้วกู้ค่าจาก backup (แถวตาม wtrs_id)

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-09-19_drop_wtrs_active_seconds.sql', 'ตัด wtrs_active_seconds (ไม่ใช้คำนวณพลังงาน)');
