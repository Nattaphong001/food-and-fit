package controllers

import (
	"food_and_fit_api/helpers"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"
)

// AdminLogin (endpoint /api/admin/login) ถูกลบแล้ว (2026-09-19) — ไม่มี client เรียกจริงเลย
// (admin-web login ผ่าน /api/login แบบ unified กับสมาชิก มาตั้งแต่แรก ดู auth_controller.go Login())
// เคยเป็น dead code ที่ logic ตั้ง sys_start_date ครั้งแรกไม่เคยถูกเรียกจริง ทำให้แอดมินใหม่
// sys_start_date เป็น NULL ค้างตลอดไป (เห็นผลจริงที่ admin_profile_view.dart + manage_admins_view.dart
// ฝั่ง admin-web) — ย้าย logic ตั้ง sys_start_date ไปรวมที่ Login() แทนแล้ว ไม่เหลือ endpoint ซ้ำอีก

// AdminLogout - ยกเลิก JWT token ของแอดมินปัจจุบันทันที (เพิ่มลง denylist) ต้องผ่าน AdminAuthMiddleware มาก่อน
func AdminLogout(c *gin.Context) {
	adminID, _ := c.Get("admin_id")

	revoked, err := helpers.RevokeCurrentToken(c)
	if !revoked {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ไม่พบข้อมูล token"})
		return
	}
	if err != nil {
		slog.Error("AdminLogout: revoke token failed", "err", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ออกจากระบบไม่สำเร็จ กรุณาลองใหม่"})
		return
	}

	if id, ok := adminID.(uint); ok {
		helpers.LogAudit(c, "admin", int(id), "logout", "")
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ออกจากระบบสำเร็จ"})
}