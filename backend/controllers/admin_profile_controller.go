package controllers

import (
	"net/http"
	"strings"
	"time"

	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// endpoint ใหม่สำหรับ C1 (ข้อมูลระบบ) + E1 (โปรไฟล์ผู้ดูแล) ในฝั่ง Admin Web
// รวมเป็นฟอร์มเดียวเพราะเป็นแถวเดียวกันใน system_data (sys_id เดียว ไม่มี multi-admin)
// ไม่แตะ AdminLogin/AdminLogout เดิม — เพิ่ม route ใหม่เท่านั้น

type UpdateAdminProfileRequest struct {
	FullName     string  `json:"sys_full_name" binding:"required"`
	Organization *string `json:"sys_organization"`
	StartDate    *string `json:"sys_start_date"` // "YYYY-MM-DD" หรือ "" เพื่อล้างค่า, ไม่ส่ง field มา = ไม่แก้
}

type ChangeAdminPasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=8"`
}

func currentAdminID(c *gin.Context) (uint, bool) {
	v, exists := c.Get("admin_id")
	if !exists {
		return 0, false
	}
	id, ok := v.(uint)
	return id, ok
}

// GetAdminProfile - GET /api/admin/profile
func GetAdminProfile(c *gin.Context) {
	adminID, ok := currentAdminID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "ไม่พบข้อมูลผู้ดูแลระบบ"})
		return
	}

	var sysUser models.SysUser
	if err := config.DB.First(&sysUser, adminID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูลผู้ดูแลระบบ"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"sys_id":           sysUser.SysID,
		"sys_email":        sysUser.SysEmail,
		"sys_full_name":    sysUser.SysFullName,
		"sys_organization": sysUser.SysOrganization,
		"sys_start_date":   sysUser.SysStartDate,
	})
}

// UpdateAdminProfile - PUT /api/admin/profile (sys_full_name / sys_organization / sys_start_date เท่านั้น
// ไม่แก้ sys_email หรือ sys_password_hash ผ่าน endpoint นี้)
func UpdateAdminProfile(c *gin.Context) {
	adminID, ok := currentAdminID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "ไม่พบข้อมูลผู้ดูแลระบบ"})
		return
	}

	var req UpdateAdminProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณากรอกชื่อ-นามสกุลให้ถูกต้อง"})
		return
	}

	var sysUser models.SysUser
	if err := config.DB.First(&sysUser, adminID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูลผู้ดูแลระบบ"})
		return
	}

	sysUser.SysFullName = req.FullName
	sysUser.SysOrganization = req.Organization

	if req.StartDate != nil {
		if *req.StartDate == "" {
			sysUser.SysStartDate = nil
		} else {
			parsed, err := time.Parse("2006-01-02", *req.StartDate)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "รูปแบบวันที่ไม่ถูกต้อง (YYYY-MM-DD)"})
				return
			}
			sysUser.SysStartDate = &parsed
		}
	}

	if err := config.DB.Save(&sysUser).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกข้อมูลไม่สำเร็จ"})
		return
	}

	helpers.LogAudit(c, "admin", int(sysUser.SysID), "update_profile", "")

	c.JSON(http.StatusOK, gin.H{
		"message":          "บันทึกข้อมูลสำเร็จ",
		"sys_id":           sysUser.SysID,
		"sys_email":        sysUser.SysEmail,
		"sys_full_name":    sysUser.SysFullName,
		"sys_organization": sysUser.SysOrganization,
		"sys_start_date":   sysUser.SysStartDate,
	})
}

// ChangeAdminPassword - PUT /api/admin/profile/password
// ต้องยืนยันรหัสผ่านเดิมก่อนเสมอ ใช้ bcrypt เดียวกับ AdminLogin (รองรับ hash เก่าที่ขึ้นต้น $2y$ จาก PHP)
// เปลี่ยนสำเร็จแล้ว revoke token ปัจจุบันทันที (เหมือน AdminLogout) บังคับ re-login ด้วย token ใหม่
func ChangeAdminPassword(c *gin.Context) {
	adminID, ok := currentAdminID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "ไม่พบข้อมูลผู้ดูแลระบบ"})
		return
	}

	var req ChangeAdminPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณากรอกรหัสผ่านเดิมและรหัสผ่านใหม่ (อย่างน้อย 8 ตัวอักษร)"})
		return
	}

	var sysUser models.SysUser
	if err := config.DB.First(&sysUser, adminID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูลผู้ดูแลระบบ"})
		return
	}

	hashStr := strings.Replace(sysUser.SysPasswordHash, "$2y$", "$2a$", 1)
	if err := bcrypt.CompareHashAndPassword([]byte(hashStr), []byte(req.OldPassword)); err != nil {
		helpers.LogAudit(c, "admin", int(sysUser.SysID), "change_password_failed", "รหัสผ่านเดิมไม่ถูกต้อง")
		c.JSON(http.StatusUnauthorized, gin.H{"error": "รหัสผ่านเดิมไม่ถูกต้อง"})
		return
	}

	newHash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถเข้ารหัสรหัสผ่านได้"})
		return
	}

	sysUser.SysPasswordHash = string(newHash)
	if err := config.DB.Save(&sysUser).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "เปลี่ยนรหัสผ่านไม่สำเร็จ"})
		return
	}

	if jti, ok := c.Get("jti"); ok {
		if jtiStr, ok := jti.(string); ok && jtiStr != "" {
			if expiresAt, ok := c.Get("token_expires_at"); ok {
				if expTime, ok := expiresAt.(time.Time); ok {
					config.DB.Create(&models.RevokedToken{Jti: jtiStr, ExpiresAt: expTime})
				}
			}
		}
	}

	helpers.LogAudit(c, "admin", int(sysUser.SysID), "change_password_success", "")

	c.JSON(http.StatusOK, gin.H{"message": "เปลี่ยนรหัสผ่านสำเร็จ กรุณาเข้าสู่ระบบใหม่"})
}
