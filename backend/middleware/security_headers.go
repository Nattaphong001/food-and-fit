package middleware

import "github.com/gin-gonic/gin"

// SecurityHeaders ตั้งค่า HTTP response header ด้านความปลอดภัยพื้นฐาน
// ป้องกัน Clickjacking (X-Frame-Options), MIME sniffing (X-Content-Type-Options)
// และจำกัดแหล่งที่มาของเนื้อหา (CSP) สำหรับ endpoint ใดที่ถูกเปิดในเบราว์เซอร์ (เช่น หน้า static/admin)
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-Frame-Options", "DENY")
		c.Header("Referrer-Policy", "no-referrer")
		c.Header("Content-Security-Policy", "default-src 'self'; frame-ancestors 'none'")
		// HSTS ส่งเฉพาะตอนคุยกันผ่าน HTTPS จริง (native TLS หรือหลัง reverse proxy ที่ terminate
		// TLS แล้วส่ง X-Forwarded-Proto ต่อมา) — ส่งตอน HTTP เฉยๆ ไม่มีความหมาย เบราว์เซอร์ไม่สนใจ
		// header นี้บน plain HTTP อยู่แล้ว แต่เช็คกันไว้ไม่ให้ทำให้ dev บนเครื่อง (HTTP ล้วน) สับสน
		if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
			c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		c.Next()
	}
}
