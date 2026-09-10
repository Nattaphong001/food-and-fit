package middleware

import (
	"food_and_fit_api/config"
	"food_and_fit_api/models"
	"food_and_fit_api/utils"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// 1. ดึง Header Authorization
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "กรุณาเข้าสู่ระบบ (Authorization header is missing)"})
			c.Abort()
			return
		}

		// 2. ตรวจสอบรูปแบบ "Bearer <token>"
		// ใช้ strings.HasPrefix เพื่อความแม่นยำ
		if !strings.HasPrefix(authHeader, "Bearer ") {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "รูปแบบ Token ไม่ถูกต้อง (Must be Bearer <token>)"})
			c.Abort()
			return
		}

		// 3. ตัดเอาเฉพาะตัว Token ออกมา
		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		tokenString = strings.TrimSpace(tokenString) // ตัดช่องว่างส่วนเกินออก

		// 4. ส่งไปตรวจสอบที่ utils
		claims, err := utils.ValidateToken(tokenString)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "สิทธิ์การเข้าถึงไม่ถูกต้องหรือหมดอายุ กรุณาเข้าสู่ระบบใหม่"})
			c.Abort()
			return
		}

		// 5. เช็คว่า token ถูก logout/revoke ไปแล้วหรือยัง (denylist)
		var revoked models.RevokedToken
		if err := config.DB.Where("jti = ?", claims.ID).First(&revoked).Error; err == nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Token นี้ถูกยกเลิกแล้ว กรุณาเข้าสู่ระบบใหม่"})
			c.Abort()
			return
		}

		// 6. บันทึก User ID + jti ลงใน Context เพื่อให้ Handler อื่นนำไปใช้ต่อได้
		c.Set("user_id", claims.MbID)
		c.Set("jti", claims.ID)
		c.Set("token_expires_at", claims.ExpiresAt.Time)
		c.Next()
	}
}