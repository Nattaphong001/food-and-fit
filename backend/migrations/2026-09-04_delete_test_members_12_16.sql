-- ลบบัญชีทดสอบ mb_id 12-16 (ของนักพัฒนาเอง ไม่ใช่ผู้ใช้จริงคนอื่น) ตามคำขอ
-- CASCADE ลบตาม: member_body_stats, member_bmr_history, daily_nutrition,
-- weight_training_result, cardio_result, member_workout_plans (→ workout_schedules)
-- ยืนยันจาก information_schema ก่อนรันว่าทุก FK ที่เกี่ยวเป็น ON DELETE CASCADE ครบ (ดู docs/SPEC.md ข้อ 3.4)
--
-- Backup ก่อนรัน: migrations/backups/backup_full_before_mwp_merge_20260904_201921.sql
-- Rollback: กู้บัญชีจาก backup ไฟล์ข้างต้นด้วย
--   mysql -u root food_and_fit_db < migrations/backups/backup_full_before_mwp_merge_20260904_201921.sql

DELETE FROM member_profile WHERE mb_id BETWEEN 12 AND 16;
