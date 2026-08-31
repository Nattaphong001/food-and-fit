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
		c.Next()
	}
}
