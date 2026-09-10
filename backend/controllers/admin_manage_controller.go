package controllers

import (
	"net/http"

	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// endpoint ใหม่สำหรับจัดการผู้ดูแลระบบหลายคน (list / create)
// ไม่แตะ AdminLogin/AdminProfile เดิม — เพิ่ม route ใหม่เท่านั้น

type CreateAdminRequest struct {
	Email        string  `json:"email" binding:"required,email"`
	FullName     string  `json:"full_name" binding:"required"`
	Organization *string `json:"organization"`
	Password     string  `json:"password" binding:"required,min=8"`
}

// ListAdmins - GET /api/admin/admins
func ListAdmins(c *gin.Context) {
	var sysUsers []models.SysUser
	if err := config.DB.Order("sys_id DESC").Find(&sysUsers).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถดึงข้อมูลผู้ดูแลระบบได้"})
		return
	}

	result := make([]gin.H, 0, len(sysUsers))
	for _, u := range sysUsers {
		result = append(result, gin.H{
			"sys_id":           u.SysID,
			"sys_email":        u.SysEmail,
			"sys_full_name":    u.SysFullName,
			"sys_organization": u.SysOrganization,
			"sys_start_date":   u.SysStartDate,
			"created_at":       u.CreatedAt,
			"updated_at":       u.UpdatedAt,
		})
	}

	c.JSON(http.StatusOK, gin.H{"data": result})
}

// CreateAdmin - POST /api/admin/admins
// รหัสผ่านตั้งโดยแอดมินที่เพิ่ม แล้วส่งมอบให้เจ้าของบัญชีโดยตรงนอกระบบ (ไม่มี OTP/อีเมล)
func CreateAdmin(c *gin.Context) {
	var req CreateAdminRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณากรอกอีเมล ชื่อ-นามสกุล และรหัสผ่าน (อย่างน้อย 8 ตัวอักษร) ให้ถูกต้อง"})
		return
	}

	var existing models.SysUser
	if err := config.DB.Where("sys_email = ?", req.Email).First(&existing).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "อีเมลนี้ถูกใช้เป็นบัญชีผู้ดูแลระบบอยู่แล้ว"})
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถเข้ารหัสรหัสผ่านได้"})
		return
	}

	// sys_start_date ไม่ถูกตั้งตอนสร้างบัญชีแล้ว — ปล่อย NULL ไว้ AdminLogin จะตั้งให้อัตโนมัติ
	// ตอน login ครั้งแรกจริง (ตรงความหมายชื่อฟิลด์ "วันที่เริ่มใช้ระบบ" มากกว่าวันที่ถูกสร้างบัญชี)
	sysUser := models.SysUser{
		SysEmail:        req.Email,
		SysPasswordHash: string(hash),
		SysFullName:     req.FullName,
		SysOrganization: req.Organization,
	}
	if err := config.DB.Create(&sysUser).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "สร้างบัญชีผู้ดูแลระบบไม่สำเร็จ"})
		return
	}

	helpers.LogAudit(c, "admin", int(sysUser.SysID), "create_admin", "")

	c.JSON(http.StatusCreated, gin.H{
		"message":          "สร้างบัญชีผู้ดูแลระบบสำเร็จ กรุณาแจ้งรหัสผ่านนี้แก่เจ้าของบัญชีโดยตรง",
		"sys_id":           sysUser.SysID,
		"sys_email":        sysUser.SysEmail,
		"sys_full_name":    sysUser.SysFullName,
		"sys_organization": sysUser.SysOrganization,
		"sys_start_date":   sysUser.SysStartDate,
	})
}
