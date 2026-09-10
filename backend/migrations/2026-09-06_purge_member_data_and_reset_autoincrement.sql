-- =====================================================================
-- 2026-09-06 : ล้างข้อมูลผู้ใช้ (ข้อมูลจำลอง) ทั้งหมด + จัดเลข AUTO_INCREMENT
-- ---------------------------------------------------------------------
-- ลบ  : member_profile และข้อมูลทุกอย่างที่สมาชิกบันทึกไว้ (6 ตารางลูก)
-- ไม่แตะ : ข้อมูลแม่ที่แอดมินป้อน (nutrition, cardio, weight_exercises,
--          แผนแม่แบบ, หมวดหมู่, muscle_group) และตารางระบบ
--          (system_data, audit_logs, revoked_tokens)
-- ไม่แตะ : PK / FK / index / ชนิดข้อมูล — รีเซ็ตเฉพาะตัวนับ AUTO_INCREMENT
--
-- backup : migrations/backups/backup_before_20260906_purge_member_data.sql
-- =====================================================================

-- STEP 1 : ลบข้อมูลผู้ใช้ (เรียงจากตารางลูกไปหาตารางแม่)
DELETE FROM member_bmr_history;
DELETE FROM weight_training_result;
DELETE FROM cardio_result;
DELETE FROM daily_nutrition;
DELETE FROM workout_schedules;
DELETE FROM member_body_stats;
DELETE FROM member_profile;

-- STEP 2 : ตารางที่ว่างแล้ว เริ่มนับ id ใหม่จาก 1
ALTER TABLE member_bmr_history     AUTO_INCREMENT = 1;
ALTER TABLE weight_training_result AUTO_INCREMENT = 1;
ALTER TABLE cardio_result          AUTO_INCREMENT = 1;
ALTER TABLE daily_nutrition        AUTO_INCREMENT = 1;
ALTER TABLE workout_schedules      AUTO_INCREMENT = 1;
ALTER TABLE member_body_stats      AUTO_INCREMENT = 1;
ALTER TABLE member_profile         AUTO_INCREMENT = 1;

-- STEP 3 : ตารางข้อมูลแม่ — ตัวนับลอยสูงกว่าค่าจริงมากเพราะเคยลบข้อมูลทดลอง
--          ตั้งกลับเป็น MAX(id)+1 (ไม่แตะแถวข้อมูลเดิมเลย แถวเก่าคง id เดิมทุกแถว)
ALTER TABLE nutrition_category      AUTO_INCREMENT = 7;    -- เดิม 10011 (เคยมีแถว id 10009/10010 ที่ลบไปแล้ว)
ALTER TABLE nutrition               AUTO_INCREMENT = 164;  -- เดิม 171
ALTER TABLE cardio_category         AUTO_INCREMENT = 3;    -- เดิม 24
ALTER TABLE cardio                  AUTO_INCREMENT = 10;   -- เดิม 29
ALTER TABLE muscle_group            AUTO_INCREMENT = 10;   -- เดิม 22
ALTER TABLE weight_exercises        AUTO_INCREMENT = 51;   -- เดิม 67
ALTER TABLE exercise_muscle_details AUTO_INCREMENT = 115;  -- เดิม 129
ALTER TABLE workout_plan_template   AUTO_INCREMENT = 5;    -- เดิม 21
ALTER TABLE plan_template_detail    AUTO_INCREMENT = 103;  -- เดิม 262
ALTER TABLE system_data             AUTO_INCREMENT = 2;    -- เดิม 3
