-- 2026-10-04 แก้ wet_equipment / wet_exercise_type ของท่าที่ไม่ตรงกับชื่อท่าและคำอธิบายท่าในตารางเอง
-- (wet_equipment: 1=Barbell 2=Dumbbell 3=Machine 4=Cable 5=Bodyweight · wet_exercise_type: 1=หลายกลุ่ม 2=เฉพาะส่วน)
-- ตรวจเทียบกับ wet_description / wet_technique ของแต่ละท่า และให้สอดคล้องกับท่าคู่เทียบที่ตั้งไว้แล้ว
-- (เช่น Incline Dumbbell Curl, Preacher Curl, Lateral Raise เป็น 2=เฉพาะส่วนอยู่แล้ว)
-- ผลต่อพลังงาน: ไม่มี — ใช้เฉพาะ wet_equipment = 5 (บอดี้เวท) ซึ่งไม่ถูกแตะ
-- ⚠️ BACKUP ก่อนรัน: mysqldump -u root --no-create-info --skip-extended-insert --complete-insert food_and_fit_db weight_exercises > weight_exercises_backup.sql

-- Dumbbell Curl: คำอธิบายใช้ดัมเบล แต่ตั้งเป็น Barbell และหลายกลุ่ม → Dumbbell + เฉพาะส่วน
UPDATE weight_exercises SET wet_equipment = 2, wet_exercise_type = 2 WHERE wet_id = 20 AND wet_name = 'Dumbbell Curl' AND wet_equipment = 1 AND wet_exercise_type = 1;

-- ท่าแยกกล้ามเนื้อที่ตั้งเป็นหลายกลุ่ม → เฉพาะส่วน
UPDATE weight_exercises SET wet_exercise_type = 2 WHERE wet_id = 4  AND wet_name = 'Dumbbell Flyes'         AND wet_exercise_type = 1;
UPDATE weight_exercises SET wet_exercise_type = 2 WHERE wet_id = 17 AND wet_name = 'Front Raise'            AND wet_exercise_type = 1;
UPDATE weight_exercises SET wet_exercise_type = 2 WHERE wet_id = 18 AND wet_name = 'Rear Delt Fly'          AND wet_exercise_type = 1;
UPDATE weight_exercises SET wet_exercise_type = 2 WHERE wet_id = 21 AND wet_name = 'Hammer Curl'            AND wet_exercise_type = 1;
UPDATE weight_exercises SET wet_exercise_type = 2 WHERE wet_id = 39 AND wet_name = 'Straight Arm Pulldown'  AND wet_exercise_type = 1;
UPDATE weight_exercises SET wet_exercise_type = 2 WHERE wet_id = 40 AND wet_name = 'Reverse Fly'            AND wet_exercise_type = 1;

-- ROLLBACK:
-- UPDATE weight_exercises SET wet_equipment = 1, wet_exercise_type = 1 WHERE wet_id = 20;
-- UPDATE weight_exercises SET wet_exercise_type = 1 WHERE wet_id IN (4, 17, 18, 21, 39, 40);
