package middleware

import (
	"food_and_fit_api/config"
	"food_and_fit_api/models"
	"food_and_fit_api/utils"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// AdminAuthMiddleware - ตรวจสอบ Token ของแอดมิน (role = "admin")
func AdminAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "กรุณาเข้าสู่ระบบแอดมินก่อน"})
			c.Abort()
			return
		}

		tokenStr := strings.TrimPrefix(authHeader, "Bearer ")

		claims, err := utils.ParseAdminToken(tokenStr)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Token ไม่ถูกต้องหรือหมดอายุ"})
			c.Abort()
			return
		}

		// เช็คว่า token ถูก logout/revoke ไปแล้วหรือยัง (denylist)
		var revoked models.RevokedToken
		if err := config.DB.Where("jti = ?", claims.ID).First(&revoked).Error; err == nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Token นี้ถูกยกเลิกแล้ว กรุณาเข้าสู่ระบบใหม่"})
			c.Abort()
			return
		}

		// เก็บ admin_id + jti ไว้ใน context เพื่อให้ handler ข้างหน้าใช้ได้
		c.Set("admin_id", claims.AdminID)
		c.Set("jti", claims.ID)
		c.Set("token_expires_at", claims.ExpiresAt.Time)
		c.Next()
	}
}