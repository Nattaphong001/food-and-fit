-- ============================================================================
-- 2026-09-14_cardio_duration_to_seconds.sql
--
-- เหตุผล: cardio_result.cdors_duration เดิมเก็บ "นาทีเต็ม" เท่านั้น (SMALLINT UNSIGNED)
-- ฝั่งมือถือปัดเศษเข้าใกล้นาทีที่สุด แต่เซสชัน 60-89 วินาที ถูกปัดเป็น "1 นาที" เท่ากันหมด
-- ทำให้พลังงานที่คำนวณคลาดเคลื่อนได้ถึง ±48% ในเซสชันสั้น (พบจากกิจกรรมเดินชัน MET 7.0 <1 นาที)
-- แก้โดยเปลี่ยนหน่วยที่เก็บจาก "นาที" เป็น "วินาที" — ไม่ต้อง ALTER TYPE เพราะ SMALLINT UNSIGNED
-- (เพดาน 65535) เก็บวินาทีได้สบาย (เพดานจริงที่ใช้ 36000 วินาที = 10 ชม. ดู
-- helpers/validation.go ValidateCardioResult) โค้ด Go/Dart แก้ไปพร้อมกันแล้วในคอมมิทนี้
--
-- ⚠️ BACKUP ก่อนรันเสมอ:
--   mysqldump -u root -p food_and_fit_db cardio_result > backend/migrations/backups/backup_cardio_result_before_duration_seconds_20260914.sql
--
-- ตรวจก่อนรันจริง — ดูว่ามีแถวไหนคูณ 60 แล้วเกิน 65535 (SMALLINT UNSIGNED) หรือไม่ (ไม่ควรมี
-- เพราะเพดานเดิม 600 นาที = 36000 วินาทีเท่านั้น):
--   SELECT cdors_id, cdors_duration FROM cardio_result WHERE cdors_duration * 60 > 65535;
-- ============================================================================

START TRANSACTION;

UPDATE cardio_result
SET cdors_duration = cdors_duration * 60
WHERE cdors_duration IS NOT NULL;

-- ตรวจผลก่อน COMMIT
SELECT cdors_id, cdors_duration FROM cardio_result ORDER BY cdors_id DESC LIMIT 20;

COMMIT;
-- ถ้าตัวเลขดูผิดปกติ ให้ ROLLBACK; แทน COMMIT; ด้านบน

-- ============================================================================
-- ROLLBACK (ถ้าต้องย้อนกลับหลัง COMMIT ไปแล้ว — แปลงวินาทีกลับเป็นนาทีเดิม)
-- ============================================================================
-- START TRANSACTION;
-- UPDATE cardio_result
-- SET cdors_duration = ROUND(cdors_duration / 60)
-- WHERE cdors_duration IS NOT NULL;
-- COMMIT;
