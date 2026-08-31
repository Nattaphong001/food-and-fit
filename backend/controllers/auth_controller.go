package controllers

import (
	"fmt"
	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"
	"food_and_fit_api/utils"
	"log"
	"math/rand"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// ==========================================
// Request Structs
// ==========================================

type RegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
	FullName string `json:"full_name" binding:"required"`
}

type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type VerifyEmailRequest struct {
	Email string `json:"email" binding:"required,email"`
	Otp   string `json:"otp" binding:"required"`
}

// ==========================================
// Handlers
// ==========================================

// Register - สมัครสมาชิกเบื้องต้น
func Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง กรุณาตรวจสอบอีเมล/รหัสผ่าน/ชื่อ"})
		return
	}

	if valid, msg := helpers.ValidatePassword(req.Password); !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถเข้ารหัสรหัสผ่านได้"})
		return
	}

	otpCode := fmt.Sprintf("%06d", rand.Intn(1000000))
	expiration := time.Now().Add(10 * time.Minute)

	var existingUser models.Member
	if err := config.DB.Where("mb_email = ?", req.Email).First(&existingUser).Error; err == nil {
		if existingUser.MbIsVerified == 1 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "อีเมลนี้มีในระบบแล้ว"})
			return
		}
		// ยังไม่ verified — อัปเดต OTP + รหัสผ่าน + ชื่อ แล้วส่งใหม่
		if err := config.DB.Model(&existingUser).Updates(map[string]interface{}{
			"mb_password_hash": string(hashedPassword),
			"mb_full_name":     req.FullName,
			"mb_otp":           otpCode,
			"mb_otp_expired":   expiration,
		}).Error; err != nil {
			log.Printf("Register: update existing user failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถบันทึกข้อมูลได้ กรุณาลองใหม่"})
			return
		}
		go func() {
			if err := helpers.SendWelcomeOTPEmail(req.Email, otpCode); err != nil {
				log.Printf("WARNING: Could not send welcome email to %s: %v", req.Email, err)
			}
		}()
		c.JSON(http.StatusOK, gin.H{"success": true, "message": "ส่งรหัส OTP ใหม่ไปที่อีเมลแล้ว กรุณายืนยันตัวตน"})
		return
	}

	member := models.Member{
		MbEmail:        req.Email,
		MbPasswordHash: string(hashedPassword),
		MbFullName:     req.FullName,
		MbOtp:          otpCode,
		MbOtpExpired:   &expiration,
		MbIsVerified:   0,
		MbGender:       1,
		MbBirthDate:    time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC),
	}

	if err := config.DB.Create(&member).Error; err != nil {
		log.Printf("Register: create member failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถบันทึกข้อมูลได้ กรุณาลองใหม่"})
		return
	}

	// หมายเหตุ: ห้าม log ค่า OTP ลง console/log แม้ตอนส่งอีเมลไม่สำเร็จ (ข้อมูลอ่อนไหว)
	go func() {
		if err := helpers.SendWelcomeOTPEmail(req.Email, otpCode); err != nil {
			log.Printf("WARNING: Could not send welcome email to %s: %v", req.Email, err)
		}
	}()

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "สมัครสมาชิกสำเร็จ กรุณาเช็คอีเมลเพื่อยืนยันตัวตน",
	})
}

// Login - เช็คทั้ง member_profile และ system_data แล้ว return role กลับ
func Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณากรอกอีเมลและรหัสผ่านให้ถูกต้อง"})
		return
	}

	// 0. เช็คว่าบัญชีนี้ถูกล็อกจากการกรอกรหัสผ่านผิดซ้ำๆ หรือไม่ (brute-force protection)
	if locked, retryAfter := helpers.CheckLoginLockout(req.Email); locked {
		helpers.LogAudit(c, "guest", 0, "login_blocked_lockout", req.Email)
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error": fmt.Sprintf("กรอกรหัสผ่านผิดหลายครั้งเกินไป กรุณาลองใหม่อีกครั้งใน %d นาที", int(retryAfter.Minutes())+1),
		})
		return
	}

	// 1. เช็ค member_profile ก่อน
	var member models.Member
	memberErr := config.DB.Where("mb_email = ?", req.Email).First(&member).Error

	if memberErr == nil {
		if member.MbIsVerified == 0 {
			c.JSON(http.StatusForbidden, gin.H{"error": "กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ"})
			return
		}
		if err := bcrypt.CompareHashAndPassword([]byte(member.MbPasswordHash), []byte(req.Password)); err != nil {
			helpers.RecordLoginFailure(req.Email)
			helpers.LogAudit(c, "member", member.MbID, "login_failed", "รหัสผ่านไม่ถูกต้อง")
			c.JSON(http.StatusUnauthorized, gin.H{"error": "อีเมลหรือรหัสผ่านไม่ถูกต้อง"})
			return
		}

		token, err := utils.GenerateToken(member.MbID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถสร้าง Token ได้"})
			return
		}
		helpers.ResetLoginFailures(req.Email)
		helpers.LogAudit(c, "member", member.MbID, "login_success", "")
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"role":    "member",
			"message": "เข้าสู่ระบบสำเร็จ",
			"token":   token,
			"user": gin.H{
				"id":        member.MbID,
				"full_name": member.MbFullName,
				"email":     member.MbEmail,
			},
		})
		return
	}

	// 2. เช็ค system_data
	var sysUser models.SysUser
	sysErr := config.DB.Where("sys_email = ?", req.Email).First(&sysUser).Error

	if sysErr == nil {
		if sysUser.SysStatus == 0 {
			helpers.LogAudit(c, "admin", int(sysUser.SysID), "login_blocked_inactive", "")
			c.JSON(http.StatusForbidden, gin.H{"error": "บัญชีนี้ถูกปิดใช้งาน กรุณาติดต่อผู้ดูแลระบบ"})
			return
		}

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
			"success": true,
			"role":    "admin",
			"message": "เข้าสู่ระบบสำเร็จ",
			"token":   token,
			"user": gin.H{
				"id":        sysUser.SysID,
				"full_name": sysUser.SysFullName,
				"email":     sysUser.SysEmail,
			},
		})
		return
	}

	c.JSON(http.StatusUnauthorized, gin.H{"error": "ไม่พบบัญชีผู้ใช้นี้ในระบบ"})
}

// VerifyEmail - ยืนยัน OTP
func VerifyEmail(c *gin.Context) {
	var req VerifyEmailRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง"})
		return
	}

	if valid, msg := helpers.ValidateOTP(req.Otp); !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	var member models.Member
	if err := config.DB.Where("mb_email = ?", req.Email).First(&member).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบอีเมลนี้ในระบบ"})
		return
	}

	if member.MbIsVerified == 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "บัญชีนี้ได้รับการยืนยันไปแล้ว"})
		return
	}

	if member.MbOtpExpired != nil && time.Now().After(*member.MbOtpExpired) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รหัส OTP หมดอายุแล้ว กรุณาขอรหัสใหม่"})
		return
	}

	if member.MbOtp != req.Otp {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รหัส OTP ไม่ถูกต้อง"})
		return
	}

	if err := config.DB.Model(&member).Updates(map[string]interface{}{
		"mb_is_verified": 1,
		"mb_otp":         "",
		"mb_otp_expired": nil,
	}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถอัปเดตสถานะได้"})
		return
	}

	token, err := utils.GenerateToken(member.MbID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ยืนยันสำเร็จแต่ไม่สามารถสร้าง Token ได้"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "ยืนยันอีเมลสำเร็จ",
		"token":   token,
		"user": gin.H{
			"id":        member.MbID,
			"full_name": member.MbFullName,
			"email":     member.MbEmail,
		},
	})
}

// ResendOTP - ส่ง OTP ใหม่สำหรับยืนยันอีเมล
func ResendOTP(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณากรอกอีเมลให้ถูกต้อง"})
		return
	}

	var member models.Member
	if err := config.DB.Where("mb_email = ?", req.Email).First(&member).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบอีเมลนี้ในระบบ"})
		return
	}

	if member.MbIsVerified == 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "บัญชีนี้ได้รับการยืนยันไปแล้ว"})
		return
	}

	newOtp := fmt.Sprintf("%06d", rand.Intn(1000000))
	expiration := time.Now().Add(10 * time.Minute)

	if err := config.DB.Model(&member).Updates(map[string]interface{}{
		"mb_otp":         newOtp,
		"mb_otp_expired": expiration,
	}).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถสร้าง OTP ใหม่ได้"})
		return
	}

	go func() {
		if err := helpers.SendWelcomeOTPEmail(req.Email, newOtp); err != nil {
			fmt.Printf("WARNING: Could not resend OTP email: %v\n", err)
		}
	}()

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "ส่งรหัส OTP ใหม่ไปที่อีเมลแล้ว",
	})
}

// Logout - ยกเลิก JWT token ปัจจุบันทันที (เพิ่มลง denylist) ต้องผ่าน AuthMiddleware มาก่อน
func Logout(c *gin.Context) {
	jti, _ := c.Get("jti")
	expiresAt, _ := c.Get("token_expires_at")
	userID, _ := c.Get("user_id")

	jtiStr, _ := jti.(string)
	expTime, ok := expiresAt.(time.Time)
	if jtiStr == "" || !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ไม่พบข้อมูล token"})
		return
	}

	revoked := models.RevokedToken{Jti: jtiStr, ExpiresAt: expTime}
	if err := config.DB.Create(&revoked).Error; err != nil {
		log.Printf("Logout: revoke token failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ออกจากระบบไม่สำเร็จ กรุณาลองใหม่"})
		return
	}

	if id, ok := userID.(int); ok {
		helpers.LogAudit(c, "member", id, "logout", "")
	}

	c.JSON(http.StatusOK, gin.H{"success": true, "message": "ออกจากระบบสำเร็จ"})
}
