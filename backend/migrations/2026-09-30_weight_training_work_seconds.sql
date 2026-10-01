-- 2026-09-30 — weight_training_result: แทน wtrs_duration (เวลารวมทั้งเซสชัน ซ้ำทุกแถว) ด้วย
-- wtrs_work_seconds (เวลาที่ใช้ทำเซตนั้น) คู่กับ wtrs_rest_seconds (เวลาพักหลังเซตนั้น) ที่มีอยู่แล้ว
--
-- เหตุผล: wtrs_duration เก็บค่าเดียวกันซ้ำทุกแถวของเซสชัน (เช่น 3 เซต = 160,160,160) ทำให้ SUM ตรงๆ
-- นับซ้ำ n เท่า และไม่มีรหัสเซสชันให้แยกรอบที่ฝึกท่าเดียวกันในวันเดียวกัน (มือถือเดาจาก wtrs_id ติดกัน
-- ซึ่งผิด) แต่ละแถวจึงเก็บเฉพาะเวลาของตัวเอง เวลารวม = SUM(wtrs_work_seconds + COALESCE(wtrs_rest_seconds,0))
-- ตรงกับที่ใช้คำนวณพลังงาน (backend รวมจากรายเซตเอง ไม่รับเวลารวมจาก client) และที่แสดงบนหน้าจอ
--
-- แถวเก่า: ไม่มีข้อมูลจริงของเวลายกรายเซต แบ่งเวลารวมเดิมหลังหักเวลาพักให้เท่ากันทุกเซตในกลุ่ม
-- (มือถือ+ท่า+วัน+wtrs_duration เดียวกัน) เศษเข้าเซตสุดท้าย ผลรวมต่อกลุ่มจึงเท่าเวลารวมเดิมพอดี
-- (ค่าประมาณ ไม่ใช่เวลาจริงรายเซต)
--
-- ⚠️ BACKUP ก่อนรัน:
--   mysqldump -u root food_and_fit_db weight_training_result > backend/migrations/backups/backup_weight_training_result_before_work_seconds_20260930.sql

ALTER TABLE weight_training_result
  ADD COLUMN wtrs_work_seconds SMALLINT UNSIGNED NULL DEFAULT NULL
  COMMENT 'เวลาที่ใช้ทำเซตนี้ (วินาที) นับตั้งแต่จบการพักรอบก่อน/เริ่มฝึก จนถึงกดพัก'
  AFTER wtrs_reps;

UPDATE weight_training_result w
JOIN (
  SELECT mb_id, wet_id, wtrs_date, wtrs_duration,
         COUNT(*) AS n,
         MAX(wtrs_id) AS last_id,
         GREATEST(wtrs_duration - COALESCE(SUM(wtrs_rest_seconds), 0), COUNT(*)) AS work_total
  FROM weight_training_result
  WHERE wtrs_duration IS NOT NULL
  GROUP BY mb_id, wet_id, wtrs_date, wtrs_duration
) g ON g.mb_id = w.mb_id AND g.wet_id <=> w.wet_id AND g.wtrs_date = w.wtrs_date AND g.wtrs_duration = w.wtrs_duration
SET w.wtrs_work_seconds = FLOOR(g.work_total / g.n)
    + IF(w.wtrs_id = g.last_id, g.work_total - FLOOR(g.work_total / g.n) * g.n, 0);

-- แถวที่ไม่เคยมีเวลา (NULL) ให้ 1 วินาที เพื่อตั้ง NOT NULL ได้
UPDATE weight_training_result SET wtrs_work_seconds = 1 WHERE wtrs_work_seconds IS NULL;

ALTER TABLE weight_training_result
  MODIFY COLUMN wtrs_work_seconds SMALLINT UNSIGNED NOT NULL
  COMMENT 'เวลาที่ใช้ทำเซตนี้ (วินาที) นับตั้งแต่จบการพักรอบก่อน/เริ่มฝึก จนถึงกดพัก',
  DROP COLUMN wtrs_duration;

-- ตรวจหลังรัน (ผลรวมต่อวัน/ท่า ต้องตรงกับเวลารวมเดิมในไฟล์ backup):
--   SELECT mb_id, wet_id, wtrs_date, SUM(wtrs_work_seconds + COALESCE(wtrs_rest_seconds, 0)) AS total_seconds
--   FROM weight_training_result GROUP BY mb_id, wet_id, wtrs_date;

-- Rollback (ต้อง restore จาก backup ข้างบนด้วย เพราะเวลารวมเดิมหายถาวร):
-- ALTER TABLE weight_training_result
--   ADD COLUMN wtrs_duration SMALLINT UNSIGNED NULL AFTER wtrs_rest_seconds,
--   DROP COLUMN wtrs_work_seconds;
-- mysql -u root food_and_fit_db < backend/migrations/backups/backup_weight_training_result_before_work_seconds_20260930.sql
