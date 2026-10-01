-- 2026-09-30 — แยก UI ท่าบอดี้เวทเป็น 2 แบบ ตามที่จริงนับจำนวนครั้งได้หรือไม่
--
-- ก่อนหน้านี้ (2026-09-29) ท่าที่ wet_equipment=5 (Bodyweight) ทุกท่าถูกตัดทั้งช่องกรอกน้ำหนักและ
-- จำนวนครั้งออกจาก UI เหมือนกันหมด — แต่จริงๆ มีแค่ Plank (wet_id=34) เท่านั้นที่เป็นท่าเกร็งค้าง
-- นับจำนวนครั้งไม่ได้จริง ส่วน Pull-up(8)/Dips(25)/Hanging Leg Raise(35)/Crunch(45) ทำกี่ครั้งก็นับได้
-- ปกติ แค่ไม่มีน้ำหนักถ่วง (ใช้น้ำหนักตัวเอง) ตัดจำนวนครั้งออกไปด้วยทำให้เสียสถิติ progression เปล่าๆ
--
-- เพิ่มคอลัมน์ wet_is_timed แยกจาก wet_equipment เพื่อให้ 2 กฎไม่ทับซ้อนกัน:
--   ช่องน้ำหนัก  แสดงเมื่อ wet_equipment != 5
--   ช่องจำนวนครั้ง แสดงเมื่อ wet_is_timed = 0
-- รองรับท่าในอนาคตทุกแบบ (เช่น ท่าค้างเวลาที่ถือน้ำหนัก, ท่าบอดี้เวทที่นับครั้ง) โดยไม่ต้องแก้โค้ดอีก
--
-- ⚠️ ก่อนรัน: backup ก่อนเสมอ
--   mysqldump -u root food_and_fit_db weight_exercises > backups/backup_weight_exercises_before_is_timed_20260930.sql

START TRANSACTION;

ALTER TABLE weight_exercises
  ADD COLUMN wet_is_timed TINYINT(1) NOT NULL DEFAULT 0
  COMMENT 'ท่าค้างเวลา ไม่มีจำนวนครั้งให้กรอก (1=ใช่ เช่น Plank, 0=นับจำนวนครั้งได้)'
  AFTER wet_mets;

UPDATE weight_exercises SET wet_is_timed = 1 WHERE wet_id = 34; -- Plank เท่านั้น

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-09-30_weight_exercises_is_timed.sql',
   'เพิ่ม weight_exercises.wet_is_timed แยกท่าค้างเวลา (Plank) ออกจากท่าบอดี้เวทที่นับครั้งได้ (Pull-up/Dips/Hanging Leg Raise/Crunch)');

COMMIT;

-- Rollback:
-- START TRANSACTION;
-- ALTER TABLE weight_exercises DROP COLUMN wet_is_timed;
-- DELETE FROM schema_migrations WHERE filename = '2026-09-30_weight_exercises_is_timed.sql';
-- COMMIT;
