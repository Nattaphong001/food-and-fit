-- =====================================================================
-- 2026-09-06 : ซ่อม FOREIGN KEY 2 ตัวที่พังจากการ ALTER ตารางแม่ member_profile
-- ---------------------------------------------------------------------
-- อาการ : หลังรัน 2026-09-06_align_defaults_and_nullability.sql (ซึ่ง MODIFY
--         COLUMN บน member_profile 2 คอลัมน์ = InnoDB rebuild ตารางแม่)
--         การ INSERT ลง member_bmr_history และ workout_schedules ด้วย mb_id
--         ที่ "มีอยู่จริง" ใน member_profile กลับติด error 1452 FK constraint
--         ทั้งที่ information_schema ยังแสดง FK ครบและชี้ตารางถูกต้อง
--         (สถานะภายในของ InnoDB หลุดจากตารางแม่ที่ถูก rebuild)
--
-- ยืนยันว่าเกิดจาก migration รอบนี้จริง ไม่ใช่ของเดิมเสีย : กู้ไฟล์ backup
--         ก่อนแก้ลงฐานทดสอบแยก (ff_fk_probe) แล้ว INSERT ชุดเดียวกันผ่านปกติ
-- สแกนครบทุก FK ในฐานแล้ว : เสียแค่ 2 ตัวนี้ ที่เหลือใช้งานได้ปกติทั้งหมด
--
-- นิยาม FK ด้านล่างคัดลอกจากไฟล์ backup บรรทัด 240 และ 642 ตรงตัว
-- (ชื่อ constraint / คอลัมน์ / ON DELETE / ON UPDATE เหมือนเดิมทุกตัวอักษร)
-- ไม่ได้เปลี่ยนดีไซน์ FK ใดๆ เป็นการซ่อมให้กลับไปเหมือนเดิมเท่านั้น
--
-- เช็คก่อนรัน : ไม่มีแถวกำพร้าทั้ง 2 ตาราง (mbh 0 แถว, wsch 0 แถว)
-- backup     : migrations/backups/backup_before_20260906_defaults_nullability.sql
-- rollback   : ไม่ต้องมี — ปลายทางคือสภาพเดียวกับก่อน migration อยู่แล้ว
-- =====================================================================

ALTER TABLE `member_bmr_history` DROP FOREIGN KEY `member_bmr_history_ibfk_1`;
ALTER TABLE `member_bmr_history` ADD CONSTRAINT `member_bmr_history_ibfk_1` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE;

ALTER TABLE `workout_schedules` DROP FOREIGN KEY `fk_wsch_member`;
ALTER TABLE `workout_schedules` ADD CONSTRAINT `fk_wsch_member` FOREIGN KEY (`mb_id`) REFERENCES `member_profile` (`mb_id`) ON DELETE CASCADE ON UPDATE CASCADE;
