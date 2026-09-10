-- Drops a duplicate FK on workout_schedules.mb_id and 4 redundant single-column mb_id
-- indexes made obsolete by the (mb_id, date) composite indexes added in
-- 2026-09-06_reapply_notnull_and_add_constraints.sql (leftmost-prefix rule means the
-- composite already covers plain mb_id lookups and FK support — keeping both just doubles
-- B-tree maintenance cost on write-heavy tables for no query benefit).
--
-- workout_schedules had two FK constraints on mb_id doing the exact same thing:
--   fk_wsch_member (intentional, named) + workout_schedules_ibfk_1 (leftover auto-generated
--   name, likely from an early ALTER before the FK was properly named/recreated).
-- Both share the same backing index (named `mb_id`) — dropping the duplicate FK constraint
-- does not touch that index, since fk_wsch_member still needs it. Left untouched.
--
-- Backup: migrations/backups/backup_schema_before_20260906_index_cleanup.sql
--
-- Rollback:
--   ALTER TABLE workout_schedules ADD CONSTRAINT workout_schedules_ibfk_1
--     FOREIGN KEY (mb_id) REFERENCES member_profile(mb_id) ON DELETE CASCADE;
--   ALTER TABLE daily_nutrition ADD KEY idx_dntt_mb_id (mb_id);
--   ALTER TABLE cardio_result ADD KEY idx_cdors_mb_id (mb_id);
--   ALTER TABLE weight_training_result ADD KEY idx_wtrs_mb_id (mb_id);
--   ALTER TABLE member_body_stats ADD KEY idx_mbs_mb_id (mb_id);

ALTER TABLE `workout_schedules` DROP FOREIGN KEY `workout_schedules_ibfk_1`;

ALTER TABLE `daily_nutrition`        DROP INDEX `idx_dntt_mb_id`;
ALTER TABLE `cardio_result`          DROP INDEX `idx_cdors_mb_id`;
ALTER TABLE `weight_training_result` DROP INDEX `idx_wtrs_mb_id`;
ALTER TABLE `member_body_stats`      DROP INDEX `idx_mbs_mb_id`;
