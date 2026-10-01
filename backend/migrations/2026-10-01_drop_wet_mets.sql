-- 2026-10-01 — ลบ weight_exercises.wet_mets (METs คงที่ต่อท่า) เปลี่ยนเป็น Dynamic METs รายเซตตาม %1RM
-- ตามบทที่ 2 ข้อ 2.1.4.12 ตารางที่ 2.3 (ดู ../../CLAUDE.md ข้อ 7[B-1])
--
-- เหตุผลที่เปลี่ยน: METs คงที่ต่อท่า × เวลา ทำให้ยกเบากับยกหนักที่ใช้เวลาเท่ากันได้พลังงานเท่ากัน
-- โมเดลใหม่เลือก METs ของแต่ละเซตจาก %1RM = น้ำหนักที่ยก / 1RM อ้างอิง (PR ก่อนเซสชัน):
--   ไม่มี 1RM (บอดี้เวท/ท่าค้างเวลา) = 3.0 · reps > 20 หรือ %1RM < 70 = 3.5 · %1RM ≥ 70 = 6.0
-- ค่า METs กลายเป็นค่าคงที่ในโค้ด (services.MetsBodyweight/MetsEndurance/MetsHeavy) ไม่ใช่ข้อมูลรายท่า
-- คอลัมน์นี้จึงไม่มีจุดใช้งานเหลือ
--
-- ⚠️ ก่อนรัน: backup ก่อนเสมอ
--   mysqldump -u root food_and_fit_db weight_exercises > backups/backup_weight_exercises_before_drop_wet_mets_20261001.sql

START TRANSACTION;

ALTER TABLE weight_exercises DROP COLUMN wet_mets;

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-10-01_drop_wet_mets.sql',
   'ลบ weight_exercises.wet_mets — METs ของเวทเลือกรายเซตตาม %1RM เทียบ PR ก่อนเซสชัน (บทที่ 2 ตารางที่ 2.3)');

COMMIT;

-- Rollback (ค่าเดิมต่อท่าอยู่ใน 2026-09-29_weight_exercises_per_exercise_mets.sql หรือไฟล์ backup):
-- START TRANSACTION;
-- ALTER TABLE weight_exercises
--   ADD COLUMN wet_mets DECIMAL(4,2) NOT NULL DEFAULT 3.50
--   COMMENT 'METs ของท่านี้ (คงที่ต่อท่า, 2024 Adult Compendium)'
--   AFTER wet_exercise_type;
-- UPDATE weight_exercises SET wet_mets = 5.00 WHERE wet_id IN (7, 26, 28, 29, 46);
-- UPDATE weight_exercises SET wet_mets = 2.80 WHERE wet_id IN (34, 35, 45);
-- UPDATE weight_exercises SET wet_mets = 3.00 WHERE wet_id IN (8, 25);
-- DELETE FROM schema_migrations WHERE filename = '2026-10-01_drop_wet_mets.sql';
-- COMMIT;
