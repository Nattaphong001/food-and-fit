-- บังคับ mb_id เป็น NOT NULL ให้ตรงกับตารางพี่น้อง (member_bmr_history.mb_id เป็น NOT NULL อยู่แล้ว)
-- ทุกแถวเจ้าของข้อมูลต้องมีเสมอ ไม่ควรมี body stat / ผลออกกำลังกายที่ไม่มีเจ้าของ
-- เช็คแล้วก่อนรัน (2026-09-04): ทั้ง 3 ตารางไม่มีแถว mb_id IS NULL เลย ปลอดภัย
-- backup ก่อนรันอยู่ที่ migrations/backups/backup_before_notnull_and_fk_fix_20260905.sql
--
-- Rollback:
--   ALTER TABLE member_body_stats MODIFY COLUMN mb_id int(11) DEFAULT NULL;
--   ALTER TABLE weight_training_result MODIFY COLUMN mb_id int(11) DEFAULT NULL;
--   ALTER TABLE cardio_result MODIFY COLUMN mb_id int(11) DEFAULT NULL;

ALTER TABLE member_body_stats
  MODIFY COLUMN mb_id int(11) NOT NULL COMMENT 'รหัสสมาชิกเจ้าของข้อมูล [FK -> member_profile]';

ALTER TABLE weight_training_result
  MODIFY COLUMN mb_id int(11) NOT NULL COMMENT 'รหัสสมาชิกเจ้าของผลการฝึก [FK -> member_profile]';

ALTER TABLE cardio_result
  MODIFY COLUMN mb_id int(11) NOT NULL COMMENT 'รหัสสมาชิกเจ้าของผลการฝึก [FK -> member_profile]';
