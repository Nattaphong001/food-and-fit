-- 2026-10-04 ปรับ wet_difficulty (1=ง่าย, 2=ปานกลาง, 3=ยาก) ของ 7 ท่า ให้สอดคล้องเกณฑ์ความซับซ้อนเชิงเทคนิค
-- (ความมั่นคง/จำนวนข้อต่อ/ภาระที่ไหล่-ลำตัว — NSCA 2023, ACSM 2009; เกณฑ์คะแนนเป็นการออกแบบของผู้วิจัย
--  รายละเอียดใน reports/เกณฑ์ระดับความยากท่าฝึก.md)
-- ผลต่อพลังงาน: ใช้เฉพาะท่าบอดี้เวท (wet_equipment=5) เลือก METs 2.8 (ยาก 1) / 3.8 (ยาก 2-3) — Dips 2→3 ยังได้ 3.8 เท่าเดิม
-- ⚠️ BACKUP ก่อนรัน: mysqldump -u root --no-create-info --skip-extended-insert --complete-insert food_and_fit_db weight_exercises > weight_exercises_backup.sql

-- ท่าเครื่อง/สายเคเบิล/ท่าข้อต่อเดียวที่มีที่รองรับ: ง่ายลง 2 → 1
UPDATE weight_exercises SET wet_difficulty = 1 WHERE wet_id = 5  AND wet_name = 'Cable Crossover'      AND wet_difficulty = 2;
UPDATE weight_exercises SET wet_difficulty = 1 WHERE wet_id = 9  AND wet_name = 'Lat Pulldown'         AND wet_difficulty = 2;
UPDATE weight_exercises SET wet_difficulty = 1 WHERE wet_id = 22 AND wet_name = 'Preacher Curl'        AND wet_difficulty = 2;
UPDATE weight_exercises SET wet_difficulty = 1 WHERE wet_id = 27 AND wet_name = 'Leg Press'            AND wet_difficulty = 2;
UPDATE weight_exercises SET wet_difficulty = 1 WHERE wet_id = 37 AND wet_name = 'Incline Dumbbell Curl' AND wet_difficulty = 2;
UPDATE weight_exercises SET wet_difficulty = 1 WHERE wet_id = 46 AND wet_name = 'Hack Squat'           AND wet_difficulty = 2;
-- Dips: ภาระที่ไหล่ (end-range extension) + ยกน้ำหนักตัวเต็ม: ยากขึ้น 2 → 3 (เท่า Pull-up)
UPDATE weight_exercises SET wet_difficulty = 3 WHERE wet_id = 25 AND wet_name = 'Dips'                 AND wet_difficulty = 2;

-- ROLLBACK:
-- UPDATE weight_exercises SET wet_difficulty = 2 WHERE wet_id IN (5, 9, 22, 27, 37, 46) AND wet_difficulty = 1;
-- UPDATE weight_exercises SET wet_difficulty = 2 WHERE wet_id = 25 AND wet_difficulty = 3;
