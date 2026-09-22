-- 2026-09-20 — เพิ่มคอลัมน์ wtrs_active_seconds กลับเข้า weight_training_result (revive)
-- ประวัติ: คอลัมน์นี้เคยมีมาก่อน (a38ae07) เก็บ "เวลาออกแรงจริงของเซตนี้" ไว้เป็นหลักฐานย้อนหลัง
-- อย่างเดียว ไม่เคยเข้าสูตรคำนวณพลังงานเลย จึงถูกตัดออกจริง (migrations/2026-09-19_
-- drop_wtrs_active_seconds.sql) — ตอนนี้ Two-Compartment Energy Model (backend/services/
-- calculator.go, CalculateWeightTrainingCalories) ต้องใช้ "เวลาออกแรงจริง" แยกจากเวลาพักจริงๆ
-- จึงต้องเพิ่มคอลัมน์นี้กลับมา คราวนี้ผูกเข้าสูตรจริง (ไม่ใช่แค่เก็บไว้เฉยๆ เหมือนรอบก่อน)
--
-- แถวเก่าทั้งหมดเป็น NULL (ย้อนหลังไม่ได้ ข้อมูลเดิมถูกลบไปตอน DROP COLUMN รอบก่อน) —
-- services.CalculateWeightTrainingCalories fallback เป็นค่าประมาณ Reps × 4 วินาที/ครั้ง
-- (จุดกึ่งกลางจังหวะ 2-8 วิ/ครั้ง — Schoenfeld, Ogborn & Krieger, 2558) เมื่อเป็น NULL
--
-- ⚠️ ก่อนรัน: backup ตารางก่อนเสมอ
--   mysqldump -u root -p food_and_fit_db weight_training_result > backups/backup_weight_training_result_before_revive_active_seconds_20260920.sql

ALTER TABLE weight_training_result
  ADD COLUMN wtrs_active_seconds SMALLINT UNSIGNED NULL DEFAULT NULL
  COMMENT 'เวลาออกแรงจริงของเซตนี้ (วินาที) - NULL=ไม่ทราบ (แถวเก่า/มือถือยังไม่ส่ง) ใช้ใน Two-Compartment Energy Model'
  AFTER wtrs_rest_seconds;

-- Rollback:
-- ALTER TABLE weight_training_result DROP COLUMN wtrs_active_seconds;

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-09-20_revive_weight_training_active_seconds.sql', 'เพิ่ม wtrs_active_seconds กลับมา ใช้กับ Two-Compartment Energy Model');
