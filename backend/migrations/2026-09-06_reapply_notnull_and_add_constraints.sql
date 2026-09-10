-- Re-apply mb_id NOT NULL (2026-09-04 fix was silently reverted by GORM AutoMigrate —
-- MemberBodyStat/WeightTrainingResult/CardioResult are in config/database.go AutoMigrate list
-- and their MbID gorm tag had no `not null`, so AutoMigrate demoted the column back to nullable
-- on next server start. Fixed the Go struct tags in the same commit as this migration so it
-- sticks this time — see models/member.go MemberBodyStat.MbID, models/exercise.go
-- WeightTrainingResult.MbID / CardioResult.MbID).
-- Also narrows member_body_stats.mbs_height to decimal(4,1) (checked live data: all rows are
-- whole-number heights stored as X.00, no precision lost) and adds missing UNIQUE/index
-- constraints reviewed against docs/SPEC.md ข้อ 3.6/D10 before writing this file.
--
-- Deliberately NOT included: UNIQUE (mb_id, mbh_record_date) on member_bmr_history — that
-- table is append-only by design (docs/SPEC.md ข้อ 3.6), adding a unique key would break
-- legitimate same-day repeat inserts. Do not add this later without re-reading that section.
--
-- Checked before running (0 rows / 0 duplicates in all cases):
--   NULL mb_id: member_body_stats, weight_training_result, cardio_result -> 0 each
--   duplicate mb_email in member_profile -> 0
-- Backup: migrations/backups/backup_before_20260906_reapply_notnull.sql
--
-- Rollback:
--   ALTER TABLE member_body_stats MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิกเจ้าของข้อมูล [FK -> member_profile]';
--   ALTER TABLE weight_training_result MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิกเจ้าของผลการฝึก [FK -> member_profile]';
--   ALTER TABLE cardio_result MODIFY COLUMN mb_id int(11) DEFAULT NULL COMMENT 'รหัสสมาชิกเจ้าของผลการฝึก [FK -> member_profile]';
--   ALTER TABLE member_body_stats MODIFY COLUMN mbs_height decimal(5,2) DEFAULT NULL COMMENT 'ส่วนสูง (ซม.)';
--   ALTER TABLE member_profile DROP INDEX uq_mb_email;
--   ALTER TABLE system_data DROP INDEX uq_sys_email;
--   ALTER TABLE daily_nutrition DROP INDEX idx_dntt_member_date;
--   ALTER TABLE cardio_result DROP INDEX idx_cdors_member_date;
--   ALTER TABLE weight_training_result DROP INDEX idx_wtrs_member_date;
--   ALTER TABLE member_body_stats DROP INDEX idx_mbs_member_date;

-- แยก 2 ALTER (รวมกันแล้ว MySQL ขึ้น error 1832 "Cannot change column 'mb_id' used in a
-- foreign key constraint" เพราะ INPLACE algorithm จัดการคอลัมน์ FK พร้อมคอลัมน์อื่นในสเตตเมนต์
-- เดียวไม่ได้ — ต้องแยกทีละ ALTER TABLE)
ALTER TABLE `member_body_stats`
  MODIFY COLUMN `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิกเจ้าของข้อมูล [FK -> member_profile]';

ALTER TABLE `member_body_stats`
  MODIFY COLUMN `mbs_height` decimal(4,1) DEFAULT NULL COMMENT 'ส่วนสูง (ซม.)';

ALTER TABLE `weight_training_result`
  MODIFY COLUMN `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิกเจ้าของผลการฝึก [FK -> member_profile]';

ALTER TABLE `cardio_result`
  MODIFY COLUMN `mb_id` int(11) NOT NULL COMMENT 'รหัสสมาชิกเจ้าของผลการฝึก [FK -> member_profile]';

ALTER TABLE `member_profile` ADD UNIQUE KEY `uq_mb_email` (`mb_email`);
ALTER TABLE `system_data`    ADD UNIQUE KEY `uq_sys_email` (`sys_email`);

ALTER TABLE `daily_nutrition`        ADD KEY `idx_dntt_member_date`  (`mb_id`,`dntt_date`);
ALTER TABLE `cardio_result`          ADD KEY `idx_cdors_member_date` (`mb_id`,`cdors_date`);
ALTER TABLE `weight_training_result` ADD KEY `idx_wtrs_member_date`  (`mb_id`,`wtrs_date`);
ALTER TABLE `member_body_stats`      ADD KEY `idx_mbs_member_date`   (`mb_id`,`mbs_recorded_date`);
