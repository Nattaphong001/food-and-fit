-- Repairs live corruption caused by GORM AutoMigrate on server restart (2026-09-06).
-- WeightTrainingResult/CardioResult gorm tags for WtrsSetNo/WtrsReps/CdorsDuration said
-- `type:int` (Go's plain `int`) while the real columns were tinyint/smallint unsigned —
-- AutoMigrate silently rewrote them to bigint(20), and WtrsDate/CdorsDate (tagged without
-- `not null`) got flipped back to nullable. Reproduced live: started `go run main.go` once
-- and queried information_schema.COLUMNS before/after — confirmed the corruption happens
-- on every restart. Fixed in the same commit: gorm tags corrected (models/exercise.go) and
-- these two structs removed from config/database.go's AutoMigrate call entirely (same
-- treatment WorkoutSchedule already got in an earlier migration).
--
-- Backup: migrations/backups/backup_before_20260906_repair_automigrate_corruption.sql
--
-- Rollback (restores the *corrupted* state — only for diagnostic purposes, never do this):
--   ALTER TABLE weight_training_result MODIFY COLUMN wtrs_date date DEFAULT NULL;
--   ALTER TABLE weight_training_result MODIFY COLUMN wtrs_set_no bigint(20) DEFAULT NULL;
--   ALTER TABLE weight_training_result MODIFY COLUMN wtrs_reps bigint(20) DEFAULT NULL;
--   ALTER TABLE weight_training_result MODIFY COLUMN wtrs_calories decimal(7,2) DEFAULT NULL;
--   ALTER TABLE cardio_result MODIFY COLUMN cdors_date date DEFAULT NULL;
--   ALTER TABLE cardio_result MODIFY COLUMN cdors_duration bigint(20) DEFAULT NULL;
--   ALTER TABLE cardio_result MODIFY COLUMN cdors_calories decimal(7,2) DEFAULT NULL;

ALTER TABLE `weight_training_result`
  MODIFY COLUMN `wtrs_date` date NOT NULL COMMENT 'วันที่บันทึกผลการฝึก';

ALTER TABLE `weight_training_result`
  MODIFY COLUMN `wtrs_set_no` tinyint UNSIGNED DEFAULT NULL COMMENT 'หมายเลขเซต';

ALTER TABLE `weight_training_result`
  MODIFY COLUMN `wtrs_reps` smallint UNSIGNED DEFAULT NULL COMMENT 'จำนวนครั้งที่ยกได้';

ALTER TABLE `weight_training_result`
  MODIFY COLUMN `wtrs_calories` decimal(6,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ)';

ALTER TABLE `cardio_result`
  MODIFY COLUMN `cdors_date` date NOT NULL COMMENT 'วันที่บันทึกผลการคาร์ดิโอ';

ALTER TABLE `cardio_result`
  MODIFY COLUMN `cdors_duration` smallint UNSIGNED DEFAULT NULL COMMENT 'ระยะเวลา (นาที)';

ALTER TABLE `cardio_result`
  MODIFY COLUMN `cdors_calories` decimal(6,2) DEFAULT NULL COMMENT 'แคลอรี่ที่เผาผลาญ (สุทธิ)';
