package helpers

import (
	"encoding/json"
	"fmt"
	"log"

	"food_and_fit_api/config"
	"food_and_fit_api/models"

	"github.com/gin-gonic/gin"
)

// LogAudit บันทึกเหตุการณ์สำคัญลง audit_logs (login, เปลี่ยนรหัสผ่าน, action ของ admin ฯลฯ)
// ไม่ทำให้ request fail แม้บันทึก log ไม่สำเร็จ — แค่ log error ไว้ฝั่ง server
func LogAudit(c *gin.Context, actorType string, actorID int, action, detail string) {
	entry := models.AuditLog{
		ActorType: actorType,
		ActorID:   actorID,
		Action:    action,
		Detail:    detail,
		IPAddress: c.ClientIP(),
	}
	if err := config.DB.Create(&entry).Error; err != nil {
		log.Printf("⚠️  audit log บันทึกไม่สำเร็จ: %v", err)
	}
}

// jsonPtrOrNil marshal ค่าที่ให้มาเป็น JSON string แล้วคืน pointer — คืน nil ถ้า v เป็น nil หรือ
// marshal ไม่ได้ (กัน column JSON พัง ดีกว่าให้ request ทั้งเส้น fail เพราะ audit log อย่างเดียว)
func jsonPtrOrNil(v interface{}) *string {
	if v == nil {
		return nil
	}
	b, err := json.Marshal(v)
	if err != nil {
		log.Printf("⚠️  audit log: marshal ค่าไม่สำเร็จ: %v", err)
		return nil
	}
	s := string(b)
	return &s
}

// LogAdminMutation บันทึก audit log เมื่อแอดมิน create/update/delete ข้อมูลตารางแม่ (S-9)
// oldValue/newValue รับ struct/nil ได้ตรงๆ — marshal เป็น JSON เก็บแยกคอลัมน์ old_value/new_value:
//   - create: oldValue=nil, newValue=struct ที่เพิ่งสร้าง
//   - update: oldValue=struct ก่อนแก้ (snapshot ต้อง copy ก่อน mutate), newValue=struct หลังแก้
//   - delete: oldValue=struct ก่อนลบ, newValue=nil
//
// Detail ยังคงเก็บ summary "table=X id=Y" ไว้เหมือนเดิมเพื่อ backward compat กับโค้ด/query ที่อ่าน
// field นี้อยู่แล้ว (ไม่ลบของเดิม แค่เพิ่มคอลัมน์ใหม่ให้ query แบบมีโครงสร้างได้)
func LogAdminMutation(c *gin.Context, action, table string, recordID interface{}, oldValue, newValue interface{}) {
	adminIDVal, _ := c.Get("admin_id")
	adminID, _ := adminIDVal.(uint)

	entry := models.AuditLog{
		ActorType: "admin",
		ActorID:   int(adminID),
		Action:    action,
		Detail:      fmt.Sprintf("table=%s id=%v", table, recordID),
		TargetTable: table,
		RecordID:    fmt.Sprintf("%v", recordID),
		OldValue:    jsonPtrOrNil(oldValue),
		NewValue:    jsonPtrOrNil(newValue),
		IPAddress:   c.ClientIP(),
	}
	if err := config.DB.Create(&entry).Error; err != nil {
		log.Printf("⚠️  audit log บันทึกไม่สำเร็จ: %v", err)
	}
}
