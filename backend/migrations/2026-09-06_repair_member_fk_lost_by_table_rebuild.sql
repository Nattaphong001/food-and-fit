-- =====================================================================
-- 2026-09-06 (รอบ 2) : ซ่อม FOREIGN KEY 4 ตัวที่หายไปจากนิยามตาราง
-- ---------------------------------------------------------------------
-- อาการ : หลัง 2026-09-06_align_defaults_and_nullability.sql (MODIFY COLUMN
--         = InnoDB rebuild ตารางลูกทั้ง 4 ตาราง) FK ที่ชี้ member_profile
--         หลุดออกจากนิยามตาราง (mysqldump/KEY_COLUMN_USAGE ไม่เห็นแล้ว)
--         แต่ InnoDB internal dictionary ยังจำชื่อ FK เดิมไว้ → กลายเป็น
--         สภาพครึ่ง ๆ : ไม่ทำ CASCADE ตอนลบสมาชิก (เกิดแถวกำพร้าได้จริง)
--         แต่กลับบล็อก DELETE FROM member_profile ด้วย error 1451 ทั้งที่
--         ตารางลูกว่างเปล่าแล้ว
--
-- ยืนยัน : ไฟล์ backup ก่อน migration รอบแรกมี FK ทั้ง 4 ตัวครบ
--          (backup_before_20260906_defaults_nullability.sql บรรทัด
--           135 / 175 / 271 / 572) นิยามด้านล่างคัดมาตรงตัวทุกตัวอักษร
--          ไม่ได้เปลี่ยนดีไซน์ FK ใด ๆ
--
-- backup : migrations/backups/backup_before_20260906_purge_member_data.sql
-- =====================================================================

ALTER TABLE `daily_nutrition` DROP FOREIGN KEY `daily_nutrition_ibfk_1`;
ALTER TABLE `member_body_stats` DROP FOREIGN KEY `fk_mbs_member`;
ALTER TABLE `cardio_result` DROP FOREIGN KEY `fk_cdors_member`;
ALTER TABLE `weight_training_result` DROP FOREIGN KEY `fk_wtrs_member`;

ALTER TABLE `daily_nutrition` ADD CONSTRAINT `daily_nutrition_ibfk_1` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE;
ALTER TABLE `member_body_stats` ADD CONSTRAINT `fk_mbs_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `cardio_result` ADD CONSTRAINT `fk_cdors_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `weight_training_result` ADD CONSTRAINT `fk_wtrs_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE;
