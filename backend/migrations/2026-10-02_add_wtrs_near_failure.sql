-- 2026-10-02 — เพิ่มคอลัมน์ wtrs_near_failure (weight_training_result)
-- เหตุผล: ท่าที่ยังไม่มีประวัติ (PR) ระบบถามผู้ใช้รายเซตว่า "หมดแรงแล้วหรือยัง" (ยกต่อได้อีกไม่เกิน 2-3 ครั้ง)
-- คำตอบนี้ใช้เลือก 1RM อ้างอิงและ METs (ดู ../../CLAUDE.md ข้อ 7[B-1] ขั้นที่ 2) แต่เดิมใช้คำนวณแล้วทิ้ง
-- ไม่เก็บ DB ทำให้คิดมือ/ตรวจย้อนหลัง/คำนวณใหม่ไม่ได้ — เก็บไว้เพื่อ audit ผลคำนวณ
--   1 = ผู้ใช้ตอบ "หมดแรงแล้ว"   0 = ตอบ "ยังยกได้อีก"
--   NULL = ไม่ได้ถาม (ท่านั้นมี PR แล้ว / ท่าบอดี้เวท-ค้างเวลา / แถวเก่าก่อน 2026-10-02)
-- คอลัมน์นี้เป็นข้อมูลดิบจากผู้ใช้ — ไม่ได้ใช้เป็นสูตร ไม่กระทบ SUM(wtrs_calories) ของ analytics
--
-- ⚠️ ก่อนรัน: backup ตารางก่อนเสมอ
--   mysqldump -u root food_and_fit_db weight_training_result > backups/backup_weight_training_result_before_near_failure_20261002.sql

START TRANSACTION;

ALTER TABLE weight_training_result
  ADD COLUMN wtrs_near_failure TINYINT(1) UNSIGNED NULL DEFAULT NULL
  COMMENT 'คำตอบผู้ใช้ตอนไม่มี PR: 1=หมดแรงแล้ว (ยกต่อได้ไม่เกิน 2-3 ครั้ง) 0=ยังยกได้อีก NULL=ไม่ได้ถาม'
  AFTER wtrs_rest_seconds;

INSERT INTO schema_migrations (filename, note) VALUES
  ('2026-10-02_add_wtrs_near_failure.sql',
   'เพิ่ม weight_training_result.wtrs_near_failure — เก็บคำตอบรายเซต "หมดแรงแล้วหรือยัง" ไว้ตรวจย้อนหลัง');

COMMIT;

-- Rollback:
-- START TRANSACTION;
-- ALTER TABLE weight_training_result DROP COLUMN wtrs_near_failure;
-- DELETE FROM schema_migrations WHERE filename = '2026-10-02_add_wtrs_near_failure.sql';
-- COMMIT;
