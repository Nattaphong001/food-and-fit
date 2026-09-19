package middleware

import (
	"crypto/rand"
	"encoding/hex"

	"github.com/gin-gonic/gin"
)

// RequestID ติด request id ต่อ request หนึ่งครั้ง — เดิมระบบไม่มีทางโยง log หลายบรรทัดของ
// request เดียวกันเข้าด้วยกันเลย (structured log เป็น JSON ต่อบรรทัดอยู่แล้ว แต่ไม่มีคีย์ร่วม)
// เคารพ "X-Request-ID" ที่ client/reverse proxy ส่งมาก่อน (ถ้ามี) ไม่งั้นสุ่มใหม่ 16 byte hex
// ใส่กลับใน response header เสมอ ให้ client เอาไปแจ้งตอนรายงานปัญหาได้ (correlate กับ log ฝั่ง
// server) และเก็บไว้ใน context คีย์ "request_id" ให้ handler/log ที่ต้องการเรียกใช้ต่อได้
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.GetHeader("X-Request-ID")
		if id == "" {
			id = generateRequestID()
		}
		c.Set("request_id", id)
		c.Header("X-Request-ID", id)
		c.Next()
	}
}

func generateRequestID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "unknown"
	}
	return hex.EncodeToString(b)
}
