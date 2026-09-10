package controllers

// [TOC]
// [SECTION] Imports
// [SECTION] Request Structs
// [STRUCT] ForgotPasswordRequest
// [STRUCT] ResetPasswordRequest
// [STRUCT] ChangePasswordRequest
// [SECTION] Handlers
// [FUNCTION] RequestOTP
// [FUNCTION] ResetPassword
// [FUNCTION] ChangePassword

// #region [SECTION] Imports
import (
	"fmt"
	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"
	"log"
	"math/rand"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// #endregion

// #region [SECTION] Request Structs
// ==========================================
// Request Structs
// ==========================================

// [STRUCT]: ForgotPasswordRequest
// Purpose: request body สำหรับขอรหัส OTP ทางอีเมล (RequestOTP)
// Inputs: Email (string, required)
// #region [STRUCT] ForgotPasswordRequest
type ForgotPasswordRequest struct {
	Email string `json:"email" binding:"required"`
}

// #endregion

// [STRUCT]: ResetPasswordRequest
// Purpose: request body สำหรับตรวจสอบ OTP และตั้งรหัสผ่านใหม่ (ResetPassword)
// Inputs: Email, OtpCode, NewPassword (ทั้งหมด required)
// #region [STRUCT] ResetPasswordRequest
type ResetPasswordRequest struct {
	Email       string `json:"email" binding:"required"`
	OtpCode     string `json:"otp_code" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// #endregion

// [STRUCT]: ChangePasswordRequest
// Purpose: request body สำหรับเปลี่ยนรหัสผ่านของผู้ใช้ที่ Login อยู่แล้ว (ChangePassword)
// Inputs: OldPassword, NewPassword (ทั้งหมด required)
// #region [STRUCT] ChangePasswordRequest
type ChangePasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required"`
}

// #endregion
// #endregion

// #region [SECTION] Handlers
// ==========================================
// Handlers
// ==========================================

// [FUNCTION]: RequestOTP
// Purpose: ฟังก์ชันสำหรับขอรหัส OTP ทางอีเมล (Public)
// Inputs: gin.Context (JSON body: ForgotPasswordRequest)
// Outputs: JSON success/error response, ส่งอีเมล OTP ไปยังผู้ใช้
// #region [FUNCTION] RequestOTP
// RequestOTP - ฟังก์ชันสำหรับขอรหัส OTP ทางอีเมล (Public)
func RequestOTP(c *gin.Context) {
	var req ForgotPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		helpers.RespondBadRequest(c, "request", "ข้อมูลไม่ถูกต้อง")
		return
	}

	// ตรวจสอบรูปแบบอีเมลผ่าน helper
	if !helpers.ValidateEmail(req.Email) {
		helpers.RespondBadRequest(c, "email", "รูปแบบอีเมลไม่ถูกต้อง")
		return
	}

	var member models.Member
	if err := config.DB.Where("mb_email = ?", req.Email).First(&member).Error; err != nil {
		// ตอบ Success เพื่อความปลอดภัย (ป้องกันการสุ่มหาอีเมลในระบบ)
		helpers.RespondSuccess(c, "หากอีเมลถูกต้อง ระบบจะส่งรหัส OTP ไปให้", nil)
		return
	}

	// สร้างรหัส OTP 6 หลัก
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	otpCode := fmt.Sprintf("%06d", r.Intn(1000000))
	expiredAt := time.Now().Add(5 * time.Minute)

	// อัปเดต OTP ลงในตาราง member_profile
	err := config.DB.Model(&member).Updates(map[string]interface{}{
		"mb_otp":         otpCode,
		"mb_otp_expired": expiredAt,
	}).Error

	if err != nil {
		helpers.RespondInternalError(c, "เกิดข้อผิดพลาดในการบันทึกข้อมูล OTP")
		return
	}

	// ส่งอีเมลจริงผ่าน Gmail SMTP helper (async กันไม่ให้ request ค้างรอ SMTP handshake)
	go func() {
		if err := helpers.SendResetPasswordEmail(req.Email, otpCode); err != nil {
			log.Printf("WARNING: Could not send reset password email to %s: %v", req.Email, err)
		}
	}()

	helpers.RespondSuccess(c, "ส่งรหัส OTP เรียบร้อยแล้ว โปรดตรวจสอบที่อีเมลของคุณ", nil)
}

// #endregion

// [FUNCTION]: ResetPassword
// Purpose: ฟังก์ชันสำหรับตรวจสอบ OTP และตั้งรหัสผ่านใหม่ (Public)
// Inputs: gin.Context (JSON body: ResetPasswordRequest)
// Outputs: JSON success/error response, อัปเดตรหัสผ่านและล้าง OTP ในฐานข้อมูล
// #region [FUNCTION] ResetPassword
// ResetPassword - ฟังก์ชันสำหรับตรวจสอบ OTP และตั้งรหัสผ่านใหม่ (Public)
func ResetPassword(c *gin.Context) {
	var req ResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		helpers.RespondBadRequest(c, "request", "กรุณากรอกข้อมูลให้ครบถ้วน")
		return
	}

	if valid, msg := helpers.ValidateOTP(req.OtpCode); !valid {
		helpers.RespondBadRequest(c, "otp_code", msg)
		return
	}

	var member models.Member
	// ค้นหาคนที่มี Email และ OTP ตรงกันในฐานข้อมูล
	if err := config.DB.Where("mb_email = ? AND mb_otp = ?", req.Email, req.OtpCode).First(&member).Error; err != nil {
		helpers.RespondBadRequest(c, "otp", "รหัส OTP ไม่ถูกต้อง")
		return
	}

	// ตรวจสอบการหมดอายุของ OTP
	if member.MbOtpExpired != nil && time.Now().After(*member.MbOtpExpired) {
		helpers.RespondBadRequest(c, "otp", "รหัส OTP หมดอายุแล้ว")
		return
	}

	// ตรวจสอบความแข็งแกร่งของรหัสผ่านใหม่ผ่าน helper
	if valid, msg := helpers.ValidatePassword(req.NewPassword); !valid {
		helpers.RespondBadRequest(c, "new_password", msg)
		return
	}

	// เข้ารหัสผ่านใหม่ (Hashing)
	hashed, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		helpers.RespondInternalError(c, "เกิดข้อผิดพลาดในการเข้ารหัสผ่าน")
		return
	}

	// อัปเดตรหัสผ่านใหม่ลงฐานข้อมูล และล้างข้อมูล OTP ออก
	updateErr := config.DB.Model(&member).Updates(map[string]interface{}{
		"mb_password_hash": string(hashed),
		"mb_otp":           "",
		"mb_otp_expired":   nil,
	}).Error

	if updateErr != nil {
		helpers.RespondInternalError(c, "ไม่สามารถบันทึกรหัสผ่านใหม่ได้")
		return
	}

	helpers.RespondSuccess(c, "เปลี่ยนรหัสผ่านสำเร็จ คุณสามารถเข้าสู่ระบบได้ทันที", nil)
}

// #endregion

// [FUNCTION]: ChangePassword
// Purpose: เปลี่ยนรหัสผ่านสำหรับผู้ใช้ที่ Login อยู่แล้ว (Protected, ต้องมี user_id จาก Middleware)
// Inputs: gin.Context (JSON body: ChangePasswordRequest, context: user_id)
// Outputs: JSON success/error response, อัปเดต mb_password_hash ในฐานข้อมูล
// #region [FUNCTION] ChangePassword
// ChangePassword - สำหรับผู้ใช้ที่ Login อยู่แล้ว และต้องการเปลี่ยนรหัสผ่าน (Protected)
func ChangePassword(c *gin.Context) {
	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		helpers.RespondBadRequest(c, "request", "กรุณากรอกข้อมูลให้ครบถ้วน")
		return
	}

	// 1. ดึง ID ของผู้ใช้จาก Token (ผ่าน Middleware)
	userID, exists := c.Get("user_id")
	if !exists {
		helpers.RespondUnauthorized(c, "ไม่พบสิทธิ์การเข้าถึง")
		return
	}

	// 2. ค้นหาข้อมูลผู้ใช้ในระบบ
	var member models.Member
	if err := config.DB.First(&member, userID).Error; err != nil {
		helpers.RespondNotFound(c, "ไม่พบข้อมูลบัญชีผู้ใช้")
		return
	}

	// 3. ตรวจสอบว่า "รหัสผ่านเดิม" ถูกต้องหรือไม่
	if err := bcrypt.CompareHashAndPassword([]byte(member.MbPasswordHash), []byte(req.OldPassword)); err != nil {
		helpers.RespondBadRequest(c, "old_password", "รหัสผ่านเดิมไม่ถูกต้อง")
		return
	}

	// 4. ตรวจสอบความแข็งแกร่งของ "รหัสผ่านใหม่"
	if valid, msg := helpers.ValidatePassword(req.NewPassword); !valid {
		helpers.RespondBadRequest(c, "new_password", msg)
		return
	}

	// 5. เข้ารหัสรหัสผ่านใหม่
	hashed, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		helpers.RespondInternalError(c, "เกิดข้อผิดพลาดในการเข้ารหัสผ่าน")
		return
	}

	// 6. อัปเดตลงฐานข้อมูล
	if err := config.DB.Model(&member).Update("mb_password_hash", string(hashed)).Error; err != nil {
		helpers.RespondInternalError(c, "ไม่สามารถเปลี่ยนรหัสผ่านได้")
		return
	}

	helpers.RespondSuccess(c, "เปลี่ยนรหัสผ่านสำเร็จ", nil)
}

// #endregion
// #endregion
