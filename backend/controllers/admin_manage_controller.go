package controllers

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// endpoint ใหม่สำหรับจัดการผู้ดูแลระบบหลายคน (list / create / deactivate)
// ไม่แตะ AdminLogin/AdminProfile เดิม — เพิ่ม route ใหม่เท่านั้น

type CreateAdminRequest struct {
	Email        string  `json:"email" binding:"required,email"`
	FullName     string  `json:"full_name" binding:"required"`
	Organization *string `json:"organization"`
	StartDate    *string `json:"start_date"` // "YYYY-MM-DD"
	Password     string  `json:"password" binding:"required,min=8"`
}

// errHandled - ใช้ส่งสัญญาณให้ Transaction rollback โดยที่ status/message ถูกตั้งไว้แล้วในตัวแปรนอกฟังก์ชันปิด
var errHandled = errors.New("handled")

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
			"sys_status":       u.SysStatus,
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

	var startDate *time.Time
	if req.StartDate != nil && *req.StartDate != "" {
		parsed, err := time.Parse("2006-01-02", *req.StartDate)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "รูปแบบวันที่ไม่ถูกต้อง (YYYY-MM-DD)"})
			return
		}
		startDate = &parsed
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถเข้ารหัสรหัสผ่านได้"})
		return
	}

	sysUser := models.SysUser{
		SysEmail:        req.Email,
		SysPasswordHash: string(hash),
		SysFullName:     req.FullName,
		SysOrganization: req.Organization,
		SysStartDate:    startDate,
		SysStatus:       1,
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
		"sys_status":       sysUser.SysStatus,
	})
}

// DeactivateAdmin - PUT /api/admin/admins/:id/deactivate
// ห้ามปิดใช้งานบัญชีตัวเอง และห้ามปิดจนไม่เหลือแอดมินที่ใช้งานได้เลย (นับภายใต้ FOR UPDATE กันแข่งกันกด)
func DeactivateAdmin(c *gin.Context) {
	currentID, ok := currentAdminID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "ไม่พบข้อมูลผู้ดูแลระบบ"})
		return
	}

	targetID, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รหัสผู้ดูแลระบบไม่ถูกต้อง"})
		return
	}

	if uint64(currentID) == targetID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ไม่สามารถปิดใช้งานบัญชีของตัวเองได้"})
		return
	}

	var statusCode int
	var message string

	txErr := config.DB.Transaction(func(tx *gorm.DB) error {
		var target models.SysUser
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&target, targetID).Error; err != nil {
			statusCode, message = http.StatusNotFound, "ไม่พบบัญชีผู้ดูแลระบบนี้"
			return err
		}

		if target.SysStatus == 0 {
			statusCode, message = http.StatusBadRequest, "บัญชีนี้ถูกปิดใช้งานอยู่แล้ว"
			return errHandled
		}

		var activeCount int64
		if err := tx.Model(&models.SysUser{}).Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("sys_status = ?", 1).Count(&activeCount).Error; err != nil {
			statusCode, message = http.StatusInternalServerError, "ไม่สามารถตรวจสอบจำนวนผู้ดูแลระบบได้"
			return err
		}

		if activeCount <= 1 {
			statusCode, message = http.StatusBadRequest, "ระบบต้องมีผู้ดูแลระบบที่ใช้งานได้อย่างน้อยหนึ่งคนเสมอ"
			return errHandled
		}

		if err := tx.Model(&target).Update("sys_status", 0).Error; err != nil {
			statusCode, message = http.StatusInternalServerError, "ปิดใช้งานบัญชีไม่สำเร็จ"
			return err
		}

		return nil
	})

	if txErr != nil {
		c.JSON(statusCode, gin.H{"error": message})
		return
	}

	helpers.LogAudit(c, "admin", int(targetID), "deactivate_admin", "")
	c.JSON(http.StatusOK, gin.H{"message": "ปิดใช้งานบัญชีสำเร็จ", "sys_id": targetID, "sys_status": 0})
}
