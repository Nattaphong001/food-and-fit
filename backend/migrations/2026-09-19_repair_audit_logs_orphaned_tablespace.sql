-- ซ่อม audit_logs orphaned InnoDB tablespace
-- อาการ: มีอยู่ใน information_schema.TABLES/SHOW TABLES แต่ CHECK TABLE / SHOW CREATE TABLE
-- ตอบ error 1932 "doesn't exist in engine" — .ibd/tablespace ไม่ตรงกับ data dictionary
-- ไม่มีข้อมูลอยู่จริงให้กู้ (engine มองว่าตารางไม่มีอยู่แล้ว) — ดู backups/backup_audit_logs_
-- orphaned_tablespace_20260919.sql สำหรับ schema อ้างอิงตอนพบปัญหา
--
-- DROP TABLE ล้าง catalog entry ที่ค้าง — GORM AutoMigrate (backend/config/database.go
-- `DB.AutoMigrate(&models.RevokedToken{}, &models.AuditLog{})`) จะสร้างตารางใหม่ให้อัตโนมัติ
-- ตอน backend เริ่มทำงานครั้งถัดไป ไม่ต้อง CREATE TABLE มือ

DROP TABLE IF EXISTS audit_logs;

-- Rollback: ไม่มี — ตารางเดิมไม่มีข้อมูลอยู่แล้ว (orphaned) ไม่มีอะไรให้ rollback กลับไป
-- ถ้าต้องการ schema กลับมาโดยไม่รอ backend เริ่มทำงาน ให้ใช้ CREATE TABLE ใน
-- backups/backup_audit_logs_orphaned_tablespace_20260919.sql (คอมเมนต์ไว้ในไฟล์นั้น)
