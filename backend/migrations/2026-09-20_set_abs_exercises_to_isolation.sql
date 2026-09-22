-- 2026-09-20 — ท่าหน้าท้องแบบน้ำหนักตัว (Plank, Hanging Leg Raise) เปลี่ยน wet_exercise_type จาก Compound เป็น Isolation
-- เหตุผล: สเปกบทที่ 2 หมวดน้ำหนักตัว ข้อ 1 "ท่าหน้าท้อง (Abs) หรือ Isolation → METs 2.8" แต่ schema มีประเภทท่าแค่
-- 2 ค่า (1=Compound, 2=Isolation) ไม่มีค่า Abs — ระบบแมป "Abs" เป็น Isolation (การตีความของผู้วิจัย ดู CLAUDE.md ข้อ 7[B-1])
-- ก่อนแก้ Plank/Hanging Leg Raise ถูกจัดเป็น Compound จึงไม่เข้าเงื่อนไข 2.8 ได้ MET 8.0/3.8/3.5 ตามเวลาพักแทน
-- ผล: resolveSetBaseMET (backend/services/calculator.go) ให้ 2.8 กับทั้ง 3 ท่า (Crunch อยู่ใน Isolation อยู่แล้ว)
-- ไม่กระทบข้อมูลเก่าใน weight_training_result (wtrs_calories เก็บค่าที่คำนวณไว้แล้ว ไม่คำนวณย้อนหลัง)
--
-- ⚠️ ก่อนรัน: backup ตารางก่อนเสมอ
--   mysqldump -u root -p food_and_fit_db weight_exercises > backups/backup_weight_exercises_before_abs_to_isolation_20260920.sql

UPDATE weight_exercises
   SET wet_exercise_type = 2
 WHERE wet_id IN (34, 35)          -- 34 = Plank, 35 = Hanging Leg Raise
   AND wet_equipment = 5
   AND wet_exercise_type = 1;

-- Rollback:
-- UPDATE weight_exercises SET wet_exercise_type = 1 WHERE wet_id IN (34, 35);
