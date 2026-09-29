-- 2026-09-29 — DROP weight_training_result.wtrs_active_seconds (เวลาออกแรงจริงต่อเซต)
--
-- เหตุผล: เป็นซากจากโมเดล Two-Compartment Energy Model (2026-09-20) ที่ถูกยกเลิกไปแล้ว
-- (2026-09-22) — ตั้งแต่นั้นมาไม่มีสูตรคำนวณพลังงานเวทเทรนนิ่งรุ่นไหนเลย (Session MET+Effort
-- Ratio, Session MET+RIR, METs คงที่ต่อท่าปัจจุบัน) ใช้ค่านี้เข้าสูตร มีแต่เก็บ DB ตรงๆ +
-- ตรวจขอบเขตความสมเหตุสมผล (helpers.ValidateWeightSession) เท่านั้น ยิ่งเก็บยิ่งเป็นภาระ
-- maintain (validation, request struct, มือถือต้องคำนวณ/ส่งค่าที่ไม่มีใครใช้จริง)
-- ดู root CLAUDE.md ข้อ 7[B-1]
--
-- ⚠️ BACKUP ก่อนรันแล้ว: backend/migrations/backups/backup_weight_training_result_before_drop_active_seconds_20260929.sql
-- (mysqldump ทั้งตาราง weight_training_result ก่อน DROP — 60 แถว ณ วันที่ backup)

ALTER TABLE weight_training_result DROP COLUMN wtrs_active_seconds;

-- Rollback (ถ้าต้องการค่ากลับมา ต้อง restore จาก backup ด้านบนด้วย เพราะ ALTER นี้ทิ้งข้อมูลเดิมถาวร):
-- ALTER TABLE weight_training_result
--   ADD COLUMN wtrs_active_seconds SMALLINT UNSIGNED NULL AFTER wtrs_rest_seconds;
-- จากนั้น: mysql -u root food_and_fit_db < backend/migrations/backups/backup_weight_training_result_before_drop_active_seconds_20260929.sql
