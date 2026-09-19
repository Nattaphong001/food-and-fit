package helpers

import (
	"time"

	"food_and_fit_api/config"
	"food_and_fit_api/models"

	"github.com/gin-gonic/gin"
)

// RevokeCurrentToken - ดึง jti/token_expires_at จาก context (ต้องผ่าน AuthMiddleware/AdminAuthMiddleware
// มาก่อน) แล้ว insert ลง revoked_tokens ทันที ใช้ร่วมกันทั้ง Logout/AdminLogout (เช็ค revoked ก่อนตอบ
// 400 ถ้าไม่มี token ให้ revoke) และ ChangePassword/ChangeAdminPassword (best-effort หลังเปลี่ยน
// รหัสผ่านสำเร็จ ไม่ block response) — เดิมโค้ดนี้อินไลน์ซ้ำ 4 จุด รวมมาไว้จุดเดียว
//
// คืน (revoked bool, err error): revoked=false, err=nil หมายถึง "ไม่มี token ให้ revoke" (เช่น
// context ไม่มี jti/token_expires_at) ไม่ใช่ error จริง — caller เป็นคนตัดสินใจว่ากรณีนี้ควรตอบ 400
// (Logout/AdminLogout) หรือเงียบๆ ผ่านไปได้ (ChangePassword/ChangeAdminPassword)
func RevokeCurrentToken(c *gin.Context) (bool, error) {
	jti, ok := c.Get("jti")
	if !ok {
		return false, nil
	}
	jtiStr, ok := jti.(string)
	if !ok || jtiStr == "" {
		return false, nil
	}
	expiresAt, ok := c.Get("token_expires_at")
	if !ok {
		return false, nil
	}
	expTime, ok := expiresAt.(time.Time)
	if !ok {
		return false, nil
	}
	if err := config.DB.Create(&models.RevokedToken{Jti: jtiStr, ExpiresAt: expTime}).Error; err != nil {
		return true, err
	}
	return true, nil
}
