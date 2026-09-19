package main

import (
	"fmt"
	"log/slog"
	"os"
	"time"

	"food_and_fit_api/config"
	"food_and_fit_api/routes"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// structured logging (log/slog, stdlib — ไม่ต้องเพิ่ม dependency ใหม่) เป็น default logger
	// ของทั้งแอป ตั้งครั้งเดียวตรงนี้ก่อนอย่างอื่นทั้งหมด — JSON ต่อบรรทัด ให้ search/grep ใน log
	// centralized ได้ง่ายกว่า fmt.Println/log.Printf ข้อความไทยเดิม (banner ตอนบูตยังคง
	// fmt.Println ไว้เหมือนเดิม อ่านง่ายกว่าตอน dev บนเครื่อง ไม่ใช่ log event ที่ต้อง query)
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))

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
			slog.Error("server failed to start (TLS)", "err", err)
			os.Exit(1)
		}
		return
	}

	if ginMode != gin.DebugMode {
		fmt.Println("⚠️  กำลังรันแบบ HTTP ธรรมดา (ไม่มี TLS) — บน production ควรวางไว้หลัง reverse proxy ที่ทำ HTTPS หรือกำหนด TLS_CERT_FILE/TLS_KEY_FILE")
	}
	if err := r.Run(serverAddr); err != nil {
		slog.Error("server failed to start", "err", err)
		os.Exit(1)
	}
}
