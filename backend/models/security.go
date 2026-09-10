package models

// [TOC]
// [SECTION] Imports
// [STRUCT] RevokedToken
// [FUNCTION] RevokedToken.TableName
// [STRUCT] AuditLog
// [FUNCTION] AuditLog.TableName

// [SECTION]: Imports — standard library deps used by structs below.
// #region [SECTION] Imports
import "time"

// #endregion

// [STRUCT]: RevokedToken mirrors DB table `revoked_tokens` — denylist of JWT jti values revoked
// before expiry (logout). Checked in AuthMiddleware/AdminAuthMiddleware on every request.
// Fields: ID (PK), Jti (JWT ID, unique), ExpiresAt, CreatedAt.
// RevokedToken เก็บ jti ของ JWT ที่ถูก logout/ยกเลิกก่อนหมดอายุ (denylist)
// ใช้เช็คใน AuthMiddleware/AdminAuthMiddleware ทุกครั้งที่มี request
// #region [STRUCT] RevokedToken
type RevokedToken struct {
	// comment: tag ต้องมีทุก field ที่ไม่ใช่ PK — GORM MigrateColumn เทียบ COLUMN_COMMENT ด้วย
	// ถ้า tag ไม่มี comment แต่ DB มี มันจะ ALTER ลบ comment ทิ้งทุกครั้งที่ restart server
	// (คอลัมน์ PK ถูกข้ามการเทียบ เลยไม่ต้องใส่)
	ID        uint      `gorm:"primaryKey;autoIncrement"`
	Jti       string    `gorm:"column:jti;type:varchar(64);uniqueIndex;not null;comment:รหัสอ้างอิงโทเคน (JWT claim jti) ที่ถูกเพิกถอน"`
	ExpiresAt time.Time `gorm:"column:expires_at;not null;index;comment:วันและเวลาที่โทเคนหมดอายุตามค่า exp ใน JWT"`
	CreatedAt time.Time `gorm:"column:created_at;autoCreateTime;not null;comment:วันและเวลาที่เพิกถอนโทเคน"`
}

// #endregion

// [FUNCTION]: TableName returns the DB table name for GORM mapping.
// Outputs: string — "revoked_tokens".
// #region [FUNCTION] RevokedToken.TableName
func (RevokedToken) TableName() string { return "revoked_tokens" }

// #endregion

// [STRUCT]: AuditLog mirrors DB table `audit_logs` — records key events (login, password change,
// admin actions) for later inspection.
// Fields: ID (PK), ActorType (member/admin/guest), ActorID, Action, Detail, TableName, RecordID,
// OldValue (JSON), NewValue (JSON), IPAddress, CreatedAt.
// TableName/RecordID/OldValue/NewValue เพิ่มเข้ามาทีหลัง (2026-08-23, migration
// 2026-08-23_audit_logs_add_mutation_columns.sql) เพื่อให้ query/diff การแก้ไขข้อมูลแม่ของแอดมิน
// ได้แบบมีโครงสร้างจริง แทนที่จะต้อง parse จาก Detail (string อิสระ) — Detail ยังคงเก็บ summary สั้นๆ
// ไว้เหมือนเดิมเพื่อ backward compat กับ query/โค้ดเก่าที่อ่านแค่ field นี้
// AuditLog บันทึกเหตุการณ์สำคัญ (login, เปลี่ยนรหัสผ่าน, action ของ admin) เพื่อตรวจสอบย้อนหลัง
// #region [STRUCT] AuditLog
type AuditLog struct {
	// comment: tag ต้องมีทุก field ที่ไม่ใช่ PK ด้วยเหตุผลเดียวกับ RevokedToken ข้างบน
	// (ข้อความต้องตรงกับ migrations/2026-09-06_fill_missing_column_comments.sql เป๊ะ ๆ
	//  ไม่งั้น AutoMigrate จะ ALTER แก้ไปมาทุกครั้งที่ restart)
	ID        uint      `gorm:"primaryKey;autoIncrement"`
	ActorType string    `gorm:"column:actor_type;type:varchar(20);index;not null;comment:ประเภทผู้กระทำ (member=สมาชิก, admin=ผู้ดูแลระบบ, guest=ยังไม่ระบุตัวตน)"` // "member" | "admin" | "guest"
	ActorID   int       `gorm:"column:actor_id;index;not null;comment:รหัสผู้กระทำ (mb_id หรือ sys_id ตาม actor_type, 0 = guest)"`
	Action    string    `gorm:"column:action;type:varchar(50);index;not null;comment:ชื่อการกระทำ (login_success, login_failed, logout, change_password_success, create, update, delete)"` // เช่น login_success, login_failed, password_change
	Detail string `gorm:"column:detail;type:varchar(255);not null;comment:รายละเอียดเพิ่มเติมของเหตุการณ์"`
	// TargetTable map ไปคอลัมน์ table_name — ตั้งชื่อ field ต่างจากคอลัมน์เพราะ "TableName" ชนกับ
	// method AuditLog.TableName() ที่ GORM ใช้หาชื่อตาราง (audit_logs) ของ struct นี้เอง
	TargetTable string `gorm:"column:table_name;type:varchar(64);index;comment:ชื่อตารางที่ถูกแก้ไข (เฉพาะ action create/update/delete)"`
	RecordID    string `gorm:"column:record_id;type:varchar(64);comment:รหัสแถวข้อมูลที่ถูกแก้ไขในตารางนั้น"`
	// OldValue/NewValue เป็น *string (ไม่ใช่ string เฉยๆ) เพราะ column เป็น JSON — MySQL/MariaDB
	// ปฏิเสธ '' (empty string) ว่าไม่ใช่ JSON ที่ถูกต้อง ต้องเป็น SQL NULL จริงๆ เวลาไม่มีค่า
	// (create ไม่มี old, delete ไม่มี new) — nil pointer ทำให้ GORM insert NULL แทน ''
	OldValue *string `gorm:"column:old_value;type:json;comment:ค่าเดิมก่อนแก้ไข (JSON, NULL เมื่อเป็นการเพิ่มข้อมูลใหม่)"`
	NewValue *string `gorm:"column:new_value;type:json;comment:ค่าใหม่หลังแก้ไข (JSON, NULL เมื่อเป็นการลบข้อมูล)"`
	IPAddress string    `gorm:"column:ip_address;type:varchar(45);not null;comment:หมายเลข IP ของผู้กระทำ (รองรับ IPv6)"`
	CreatedAt time.Time `gorm:"column:created_at;autoCreateTime;index;not null;comment:วันและเวลาที่บันทึกเหตุการณ์"`
}

// #endregion

// [FUNCTION]: TableName returns the DB table name for GORM mapping.
// Outputs: string — "audit_logs".
// #region [FUNCTION] AuditLog.TableName
func (AuditLog) TableName() string { return "audit_logs" }

// #endregion
