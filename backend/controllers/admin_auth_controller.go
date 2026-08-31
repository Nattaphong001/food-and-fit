package controllers

import (
	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"
	"food_and_fit_api/utils"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type AdminLoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

func AdminLogin(c *gin.Context) {
	var req AdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณากรอกอีเมลและรหัสผ่านให้ถูกต้อง"})
		return
	}

	if locked, retryAfter := helpers.CheckLoginLockout(req.Email); locked {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error": fmt.Sprintf("กรอกรหัสผ่านผิดหลายครั้งเกินไป กรุณาลองใหม่อีกครั้งใน %d นาที", int(retryAfter.Minutes())+1),
		})
		return
	}

	var sysUser models.SysUser
	if err := config.DB.Where("sys_email = ?", req.Email).First(&sysUser).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "อีเมลหรือรหัสผ่านไม่ถูกต้อง"})
		return
	}

	if sysUser.SysStatus == 0 {
		helpers.LogAudit(c, "admin", int(sysUser.SysID), "login_blocked_inactive", "")
		c.JSON(http.StatusForbidden, gin.H{"error": "บัญชีนี้ถูกปิดใช้งาน กรุณาติดต่อผู้ดูแลระบบ"})
		return
	}

	// แปลง $2y$ (PHP) → $2a$ (Go) เพื่อให้ bcrypt อ่านได้
	hashStr := strings.Replace(sysUser.SysPasswordHash, "$2y$", "$2a$", 1)
	if err := bcrypt.CompareHashAndPassword([]byte(hashStr), []byte(req.Password)); err != nil {
		helpers.RecordLoginFailure(req.Email)
		helpers.LogAudit(c, "admin", int(sysUser.SysID), "login_failed", "รหัสผ่านไม่ถูกต้อง")
		c.JSON(http.StatusUnauthorized, gin.H{"error": "อีเมลหรือรหัสผ่านไม่ถูกต้อง"})
		return
	}

	token, err := utils.GenerateAdminToken(sysUser.SysID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถสร้าง Token ได้"})
		return
	}

	helpers.ResetLoginFailures(req.Email)
	helpers.LogAudit(c, "admin", int(sysUser.SysID), "login_success", "")

	c.JSON(http.StatusOK, gin.H{
		"message": "เข้าสู่ระบบสำเร็จ",
		"token":   token,
		"admin": gin.H{
			"id":           sysUser.SysID,
			"full_name":    sysUser.SysFullName,
			"email":        sysUser.SysEmail,
			"organization": sysUser.SysOrganization,
		},
	})
}

// AdminLogout - ยกเลิก JWT token ของแอดมินปัจจุบันทันที (เพิ่มลง denylist) ต้องผ่าน AdminAuthMiddleware มาก่อน
func AdminLogout(c *gin.Context) {
	jti, _ := c.Get("jti")
	expiresAt, _ := c.Get("token_expires_at")
	adminID, _ := c.Get("admin_id")

	jtiStr, _ := jti.(string)
	expTime, ok := expiresAt.(time.Time)
	if jtiStr == "" || !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ไม่พบข้อมูล token"})
		return
	}

	revoked := models.RevokedToken{Jti: jtiStr, ExpiresAt: expTime}
	if err := config.DB.Create(&revoked).Error; err != nil {
		log.Printf("AdminLogout: revoke token failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ออกจากระบบไม่สำเร็จ กรุณาลองใหม่"})
		return
	}

	if id, ok := adminID.(uint); ok {
		helpers.LogAudit(c, "admin", int(id), "logout", "")
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ออกจากระบบสำเร็จ"})
}