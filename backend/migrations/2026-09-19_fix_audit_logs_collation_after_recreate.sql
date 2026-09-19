-- แก้ collation ของ audit_logs ที่เพี้ยนหลัง GORM AutoMigrate สร้างตารางใหม่ (จากการซ่อม
-- orphaned tablespace ใน 2026-09-19_repair_audit_logs_orphaned_tablespace.sql รอบเดียวกัน)
--
-- สาเหตุ: struct AuditLog (models/security.go) ไม่ได้ระบุ collation ใน gorm tag เลย —
-- ตอน DROP+AutoMigrate สร้างใหม่ MySQL ใช้ collation default ของ server/database แทน
-- (@@collation_database = utf8mb4_general_ci) ทำให้ audit_logs กลายเป็น general_ci ทั้งตาราง
-- ขัดกับ root CLAUDE.md ข้อ D6 ที่ยืนยันไว้ (2026-09-11) ว่าทุกตารางใน food_and_fit_db เป็น
-- utf8mb4_unicode_ci ตรงกันหมดแล้ว — ตาราง revoked_tokens (autoMigrate คู่กัน) ยังเป็น
-- unicode_ci ปกติเพราะไม่ได้ถูก DROP+recreate รอบนี้ ยืนยัน bug เกิดเฉพาะจากการ recreate
--
-- ไม่แตะ old_value/new_value (utf8mb4_bin) — เป็นคอลัมน์ JSON ที่ GORM ตั้ง collation แบบ bin
-- ให้เองเสมอ ไม่เกี่ยวกับ D6 (D6 พูดถึง text collation ปกติ ไม่ใช่ JSON storage column)

ALTER TABLE audit_logs
  MODIFY COLUMN actor_type varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
    COMMENT 'ประเภทผู้กระทำ (member=สมาชิก, admin=ผู้ดูแลระบบ, guest=ยังไม่ระบุตัวตน)',
  MODIFY COLUMN action varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
    COMMENT 'ชื่อการกระทำ (login_success, login_failed, logout, change_password_success, create, update, delete)',
  MODIFY COLUMN detail varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
    COMMENT 'รายละเอียดเพิ่มเติมของเหตุการณ์',
  MODIFY COLUMN table_name varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL
    COMMENT 'ชื่อตารางที่ถูกแก้ไข (เฉพาะ action create/update/delete)',
  MODIFY COLUMN record_id varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL
    COMMENT 'รหัสแถวข้อมูลที่ถูกแก้ไขในตารางนั้น',
  MODIFY COLUMN ip_address varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
    COMMENT 'หมายเลข IP ของผู้กระทำ (รองรับ IPv6)',
  COLLATE=utf8mb4_unicode_ci;

-- Rollback (กลับไป general_ci ที่ AutoMigrate สร้างให้ตอนแรก — ไม่แนะนำ ทำไว้เผื่อจำเป็นจริงๆ):
-- ALTER TABLE audit_logs
--   MODIFY COLUMN actor_type varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL
--     COMMENT 'ประเภทผู้กระทำ (member=สมาชิก, admin=ผู้ดูแลระบบ, guest=ยังไม่ระบุตัวตน)',
--   MODIFY COLUMN action varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL
--     COMMENT 'ชื่อการกระทำ (login_success, login_failed, logout, change_password_success, create, update, delete)',
--   MODIFY COLUMN detail varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL
--     COMMENT 'รายละเอียดเพิ่มเติมของเหตุการณ์',
--   MODIFY COLUMN table_name varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL
--     COMMENT 'ชื่อตารางที่ถูกแก้ไข (เฉพาะ action create/update/delete)',
--   MODIFY COLUMN record_id varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL
--     COMMENT 'รหัสแถวข้อมูลที่ถูกแก้ไขในตารางนั้น',
--   MODIFY COLUMN ip_address varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL
--     COMMENT 'หมายเลข IP ของผู้กระทำ (รองรับ IPv6)',
--   COLLATE=utf8mb4_general_ci;
