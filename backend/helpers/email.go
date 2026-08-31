package helpers

import (
	"fmt"
	"net/smtp"
	"os"
)

const (
	smtpHost = "smtp.gmail.com"
	smtpPort = "587"
)

// =====================================================================
// 1. ฟังก์ชันส่งรหัส OTP สำหรับเปลี่ยนรหัสผ่าน (Forgot Password)
// =====================================================================
func SendResetPasswordEmail(targetEmail string, otp string) error {
	subject := "Subject: Food & Fit - รหัสยืนยันการเปลี่ยนรหัสผ่าน\n"
	mime := "MIME-version: 1.0;\nContent-Type: text/html; charset=\"UTF-8\";\n\n"
	body := fmt.Sprintf(`
        <div style="font-family: sans-serif; border: 1px solid #ddd; padding: 20px; border-radius: 10px;">
            <h2 style="color: #4CAF50;">Food & Fit Support</h2>
            <p>คุณได้รับรหัส OTP เพื่อใช้ในการตั้งรหัสผ่านใหม่:</p>
            <div style="font-size: 32px; font-weight: bold; color: #333; letter-spacing: 5px; margin: 20px 0;">%s</div>
            <p style="color: #666;">รหัสนี้จะหมดอายุภายใน 5 นาที</p>
            <p style="font-size: 12px; color: #999;">หากคุณไม่ได้ขอนี้ โปรดลบอีเมลฉบับนี้ทิ้ง</p>
        </div>
    `, otp)

	message := []byte(subject + mime + body)
	smtpEmail := os.Getenv("SMTP_EMAIL")
	smtpPassword := os.Getenv("SMTP_PASSWORD")
	if smtpEmail == "" || smtpPassword == "" {
		return fmt.Errorf("SMTP credentials not configured")
	}
	auth := smtp.PlainAuth("", smtpEmail, smtpPassword, smtpHost)

	return smtp.SendMail(smtpHost+":"+smtpPort, auth, smtpEmail, []string{targetEmail}, message)
}

// =====================================================================
// 2. ฟังก์ชันส่งรหัส OTP สำหรับยืนยันการสมัครสมาชิกใหม่ (Register)
// =====================================================================
func SendWelcomeOTPEmail(targetEmail string, otp string) error {
	subject := "Subject: ยินดีต้อนรับสู่ Food & Fit - รหัสยืนยันการสมัครสมาชิก\n"
	mime := "MIME-version: 1.0;\nContent-Type: text/html; charset=\"UTF-8\";\n\n"
	body := fmt.Sprintf(`
        <div style="font-family: sans-serif; border: 1px solid #ddd; padding: 20px; border-radius: 10px; border-top: 5px solid #4CAF50;">
            <h2 style="color: #4CAF50;">ยินดีต้อนรับสู่ Food & Fit!</h2>
            <p>ขอบคุณที่ร่วมเป็นส่วนหนึ่งกับเรา เพื่อเสร็จสิ้นการสมัครสมาชิก โปรดใช้รหัส OTP ด้านล่างนี้เพื่อยืนยันอีเมลของคุณ:</p>
            <div style="text-align: center; background: #f9f9f9; padding: 20px; margin: 20px 0;">
                <span style="font-size: 32px; font-weight: bold; color: #333; letter-spacing: 5px;">%s</span>
            </div>
            <p style="color: #666;">รหัสยืนยันนี้จะหมดอายุภายใน <b>5 นาที</b></p>
            <hr style="border: none; border-top: 1px solid #eee;">
            <p style="font-size: 12px; color: #999;">หากคุณไม่ได้สมัครสมาชิกกับเรา โปรดเพิกเฉยต่ออีเมลฉบับนี้</p>
        </div>
    `, otp)

	message := []byte(subject + mime + body)
	smtpEmail := os.Getenv("SMTP_EMAIL")
	smtpPassword := os.Getenv("SMTP_PASSWORD")
	if smtpEmail == "" || smtpPassword == "" {
		return fmt.Errorf("SMTP credentials not configured")
	}
	auth := smtp.PlainAuth("", smtpEmail, smtpPassword, smtpHost)

	return smtp.SendMail(smtpHost+":"+smtpPort, auth, smtpEmail, []string{targetEmail}, message)
}
