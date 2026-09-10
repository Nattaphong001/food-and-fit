package utils

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"log"
	"os"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// โหลดแบบ lazy (ไม่ใช่ package-level var init ตรงๆ) เพราะ main() เพิ่งเรียก godotenv.Load(".env")
// ตอนเข้า main() — ถ้า evaluate ตอน package init จะยังอ่านค่า JWT_SECRET จาก .env ไม่ได้เลย
var (
	jwtSecretOnce  sync.Once
	jwtSecretValue []byte
)

func getJWTSecret() []byte {
	jwtSecretOnce.Do(func() {
		s := os.Getenv("JWT_SECRET")
		if s == "" {
			log.Fatal("❌ JWT_SECRET is not set. กรุณาตั้งค่า JWT_SECRET ในไฟล์ .env ก่อนรันเซิร์ฟเวอร์ (ห้ามปล่อยว่างหรือใช้ค่า default)")
		}
		jwtSecretValue = []byte(s)
	})
	return jwtSecretValue
}

// newJTI สุ่มรหัสประจำ token แต่ละใบ ใช้เทียบกับ RevokedToken ตอน logout
func newJTI() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// ==========================================
// Member Token
// ==========================================

type Claims struct {
	MbID int `json:"mb_id"`
	jwt.RegisteredClaims
}

// GenerateToken สร้าง JWT Token หลังจาก Login สำเร็จ
func GenerateToken(mbID int) (string, error) {
	expirationTime := time.Now().Add(24 * time.Hour)

	claims := &Claims{
		MbID: mbID,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        newJTI(),
			ExpiresAt: jwt.NewNumericDate(expirationTime),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(getJWTSecret())
}

// ValidateToken ตรวจสอบว่า Token ถูกต้องหรือไม่
func ValidateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return getJWTSecret(), nil
	})

	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token claims")
	}

	return claims, nil
}

// ==========================================
// Admin Token
// ==========================================

type AdminClaims struct {
	AdminID uint   `json:"admin_id"`
	Role    string `json:"role"`
	jwt.RegisteredClaims
}

// GenerateAdminToken สร้าง JWT Token สำหรับแอดมิน
func GenerateAdminToken(adminID uint) (string, error) {
	claims := &AdminClaims{
		AdminID: adminID,
		Role:    "admin",
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        newJTI(),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(getJWTSecret())
}

// ParseAdminToken ตรวจสอบ Token และยืนยันว่าเป็นแอดมิน
func ParseAdminToken(tokenString string) (*AdminClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &AdminClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return getJWTSecret(), nil
	})

	if err != nil {
		return nil, err
	}

	claims, ok := token.Claims.(*AdminClaims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token claims")
	}

	if claims.Role != "admin" {
		return nil, errors.New("ไม่มีสิทธิ์แอดมิน")
	}

	return claims, nil
}