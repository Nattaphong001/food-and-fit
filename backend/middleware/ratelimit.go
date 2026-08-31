package middleware

// [TOC]
// [SECTION] Imports
// [STRUCT] bucket
// [MIDDLEWARE] RateLimitMiddleware

// [SECTION]: Imports — stdlib (net/http, sync, time) + gin framework
// #region [SECTION] Imports
import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// #endregion

// [STRUCT]: bucket
// Purpose: ตัวนับ request แบบ fixed-window ต่อ key หนึ่งตัว (ปกติคือ client IP)
// #region [STRUCT] bucket
// bucket คือตัวนับ request แบบ fixed-window ต่อ key หนึ่งตัว (ปกติคือ client IP)
type bucket struct {
	count       int
	windowStart time.Time
}

// #endregion

// [MIDDLEWARE]: RateLimitMiddleware
// Purpose: จำกัดจำนวน request ต่อ client IP ภายในช่วงเวลาที่กำหนด ป้องกัน DoS/brute-force
// Inputs: maxRequests (จำนวน request สูงสุดต่อ window), window (ช่วงเวลานับ) -> คืนค่า gin.HandlerFunc
// Outputs: ถ้าเกิน limit ตอบ 429 + c.Abort(); ถ้าไม่เกิน เรียก c.Next() ต่อ
// #region [MIDDLEWARE] RateLimitMiddleware
// RateLimitMiddleware จำกัดจำนวน request ต่อ client IP ภายในช่วงเวลาที่กำหนด
// ป้องกันการยิง request รัว ๆ (DoS) และช่วยชะลอการ brute-force
// หมายเหตุ: เก็บ state ใน memory — เหมาะกับเซิร์ฟเวอร์ instance เดียว ถ้า scale หลาย instance ควรย้ายไป Redis
func RateLimitMiddleware(maxRequests int, window time.Duration) gin.HandlerFunc {
	var mu sync.Mutex
	buckets := make(map[string]*bucket)

	// เก็บกวาด entry เก่าเป็นระยะ กัน memory โตไม่จำกัด
	go func() {
		ticker := time.NewTicker(window * 2)
		defer ticker.Stop()
		for range ticker.C {
			mu.Lock()
			now := time.Now()
			for k, b := range buckets {
				if now.Sub(b.windowStart) > window*2 {
					delete(buckets, k)
				}
			}
			mu.Unlock()
		}
	}()

	return func(c *gin.Context) {
		key := c.ClientIP()

		mu.Lock()
		b, ok := buckets[key]
		now := time.Now()
		if !ok || now.Sub(b.windowStart) > window {
			b = &bucket{count: 0, windowStart: now}
			buckets[key] = b
		}
		b.count++
		exceeded := b.count > maxRequests
		mu.Unlock()

		if exceeded {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "มีการเรียกใช้งานถี่เกินไป กรุณาลองใหม่ภายหลัง"})
			c.Abort()
			return
		}

		c.Next()
	}
}

// #endregion
