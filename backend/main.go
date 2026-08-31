package main

import (
	"fmt"
	"log"
	"os"
	"time"

	"food_and_fit_api/config"
	"food_and_fit_api/routes"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// โหลด .env file
	_ = godotenv.Load(".env")

	time.Local = time.FixedZone("Asia/Bangkok", 7*3600)

	// 1. เชื่อมต่อฐานข้อมูล
	config.ConnectDatabase()

	// 2. ตั้งค่าโหมด Gin ตาม GIN_MODE ใน .env — default เป็น release เสมอ
	// (ต้องตั้ง GIN_MODE=debug เองใน .env ตอน dev บนเครื่องเท่านั้น ห้าม hardcode debug ไว้)
	ginMode := os.Getenv("GIN_MODE")
	if ginMode == "" {
		ginMode = gin.ReleaseMode
	}
	gin.SetMode(ginMode)

	// 3. ตั้งค่า Routes
	r := routes.SetupRouter()

	// 4. อ่าน PORT จาก .env หรือใช้ default
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	serverAddr := fmt.Sprintf("0.0.0.0:%s", port)
	fmt.Printf("🚀 Server is starting on http://localhost:%s (mode=%s)\n", port, ginMode)
	fmt.Println("📡 API Base URL: http://localhost:" + port + "/api")

	// 5. รัน Server — ถ้าตั้ง TLS_CERT_FILE/TLS_KEY_FILE ไว้ใน .env จะรันเป็น HTTPS แทน HTTP ธรรมดา
	certFile := os.Getenv("TLS_CERT_FILE")
	keyFile := os.Getenv("TLS_KEY_FILE")
	if certFile != "" && keyFile != "" {
		fmt.Println("🔒 TLS enabled")
		if err := r.RunTLS(serverAddr, certFile, keyFile); err != nil {
			log.Fatalf("❌ Server failed to start (TLS): %v", err)
		}
		return
	}

	if ginMode != gin.DebugMode {
		fmt.Println("⚠️  กำลังรันแบบ HTTP ธรรมดา (ไม่มี TLS) — บน production ควรวางไว้หลัง reverse proxy ที่ทำ HTTPS หรือกำหนด TLS_CERT_FILE/TLS_KEY_FILE")
	}
	if err := r.Run(serverAddr); err != nil {
		log.Fatalf("❌ Server failed to start: %v", err)
	}
}
