-- 2026-09-19_fix_cardio_result_duration_minutes_to_seconds.sql
--
-- เหตุผล: ตรวจข้อมูลจริงในดัมป์ food_and_fit_db (12).sql พบว่า cardio_result.cdors_duration
-- ทุกแถว (203 แถว, mb_id 1-10, ค่าอยู่ในช่วง 15-45 ทั้งหมด) ยังเก็บเป็น "นาที" อยู่ ทั้งที่
-- migrations/2026-09-14_cardio_duration_to_seconds.sql เปลี่ยนหน่วยคอลัมน์นี้เป็น "วินาที"
-- ไปแล้ว และ controllers/workout_controller.go (SaveCardioResult) คำนวณ
-- burnedCalories = netMets * bodyWeight * (cdors_duration/3600.0) โดยสมมติว่าเป็นวินาทีเสมอ
--
-- ยืนยันด้วยการคำนวณมือ 2 แถวตัวอย่าง (คูณ 60 แล้วตรงกับ cdors_calories ที่เก็บไว้เป๊ะ):
--   id=2: duration=15 (นาที) -> (15*60/3600)*6.0*82.28 = 123.42 = cdors_calories ที่เก็บไว้จริง
--   id=4: duration=36 (นาที) -> (36*60/3600)*6.5*81.74 = 318.79 = cdors_calories ที่เก็บไว้จริง
-- แปลว่า cdors_calories ที่เก็บไว้ถูกต้องแล้ว (คำนวณด้วยเวลาจริงถูกต้อง) แต่ cdors_duration
-- ที่บันทึกลงคอลัมน์ลืมคูณ 60 ก่อนเก็บ — เป็นข้อมูล demo/seed (ไม่ได้ผ่าน endpoint
-- SaveCardioResult จริง สันนิษฐานว่ามาจาก backend/cmd_seed_demo.exe ซึ่งเป็นไฟล์ .exe
-- คอมไพล์แล้วอย่างเดียว ไม่มีซอร์สโค้ดอยู่ในโปรเจกต์ให้ตรวจสอบ) ไม่ใช่บั๊กที่ตัว endpoint จริง
--
-- Migration นี้แก้เฉพาะ cdors_duration (คูณ 60) — ไม่แตะ cdors_calories เพราะค่านั้นถูกต้องอยู่แล้ว
-- ค่าที่มากที่สุดหลังคูณ 60 คือ 45*60=2700 วินาที ยังต่ำกว่าเพดาน 36000 วินาที (10 ชม.) ของ
-- helpers/validation.go ValidateCardioResult มาก ปลอดภัยที่จะคูณทั้งตารางโดยไม่ต้องกรองแถว
--
-- ⚠️ ก่อนรัน: backup ตารางก่อนเสมอ
--   mysqldump -u root -p food_and_fit_db cardio_result > backend/migrations/backups/backup_cardio_result_before_duration_unit_fix_20260919.sql

START TRANSACTION;

UPDATE cardio_result
SET cdors_duration = cdors_duration * 60;

-- ตรวจผลก่อน COMMIT — ควรเห็นค่าทุกแถวอยู่ในช่วง 900-2700 (แทน 15-45 เดิม)
SELECT MIN(cdors_duration), MAX(cdors_duration), COUNT(*) FROM cardio_result;

COMMIT;
-- ถ้าตัวเลขดูผิดปกติ ให้ ROLLBACK; แทน COMMIT; ด้านบน

-- ============================================================================
-- ROLLBACK (ถ้าต้องย้อนกลับหลัง COMMIT ไปแล้ว)
-- ============================================================================
-- START TRANSACTION;
-- UPDATE cardio_result
-- SET cdors_duration = ROUND(cdors_duration / 60);
-- COMMIT;
