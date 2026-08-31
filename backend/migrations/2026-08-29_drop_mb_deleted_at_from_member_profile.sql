-- ตัดฟีเจอร์ "ลบบัญชีสมาชิก / Grace Period" ออกทั้งระบบ — ยืนยันแล้วว่าไม่เคยมี endpoint ไหน
-- (ทั้งแอปมือถือและ admin web) set mb_status=2 จริง มีแต่โครง backend (cron hard-delete +
-- auto-restore ตอน login) เขียนรอไว้เฉยๆ ไม่เคยถูก trigger — ตัดสินใจไม่ทำฟีเจอร์นี้แล้ว
-- (ดู CLAUDE.md หัวข้อ 4 D8) เหลือ mb_status = 1 (Active) ค่าเดียว
-- ได้ backup ตาราง member_profile ไว้ที่ migrations/backups/backup_member_profile_before_drop_mb_deleted_at_20260829.sql ก่อนรันไฟล์นี้แล้ว
-- ต้อง sync ER Diagram + เอกสารบทที่ 4 (นอก repo) ตามไปด้วย

ALTER TABLE member_profile DROP COLUMN mb_deleted_at;
