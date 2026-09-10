package config

import (
	"fmt"
	"log"
	"os"
	"time"

	"food_and_fit_api/models"
	"github.com/joho/godotenv"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

var DB *gorm.DB

func ConnectDatabase() {
	err := godotenv.Load(".env")
	if err != nil {
		if err := godotenv.Load(); err != nil {
			log.Println("Warning: .env file not found, will use environment variables")
		}
	}

	dbUser := os.Getenv("DB_USER")
	if dbUser == "" {
		dbUser = "root"
	}

	dbPass := os.Getenv("DB_PASS")
	dbHost := os.Getenv("DB_HOST")
	if dbHost == "" {
		dbHost = "127.0.0.1"
	}

	dbPort := os.Getenv("DB_PORT")
	if dbPort == "" {
		dbPort = "3306"
	}

	dbName := os.Getenv("DB_NAME")
	if dbName == "" {
		dbName = "food_and_fit-2"
	}

	// timeout=30s ป้องกัน dial hang, parseTime+loc คงเดิม
	dsn := fmt.Sprintf(
		"%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local&timeout=30s&readTimeout=30s&writeTimeout=30s",
		dbUser, dbPass, dbHost, dbPort, dbName,
	)

	log.Printf("🔗 Connecting to database: %s:%s@%s:%s/%s", dbUser, "***", dbHost, dbPort, dbName)

	database, err := gorm.Open(mysql.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("❌ Failed to connect to database! Error: %v", err)
	}

	// ตั้งค่า connection pool ป้องกัน "invalid connection"
	sqlDB, err := database.DB()
	if err != nil {
		log.Fatalf("❌ Failed to get sql.DB: %v", err)
	}
	sqlDB.SetMaxOpenConns(25)
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetConnMaxLifetime(30 * time.Minute) // ต่ำกว่า MySQL wait_timeout (8h)
	sqlDB.SetConnMaxIdleTime(10 * time.Minute) // recycle connection ที่ idle นาน

	DB = database

	// WeightTrainingResult, CardioResult, MemberBodyStat ถอดออกจาก AutoMigrate ถาวรแล้ว
	// (2026-09-06, ก่อนหน้านี้เคยมี AutoMigrate(&models.WeightTrainingResult{},
	// &models.CardioResult{}, &models.MemberBodyStat{}) ตรงนี้ — เจอบั๊กจริงระหว่างไล่แก้
	// mb_id NOT NULL: gorm tag ของ struct 3 ตัวนี้ตรงกับ DB จริงไม่ครบ (type/size/not null)
	// ทำให้ AutoMigrate เงียบๆ เด้ง schema กลับทุกครั้งที่ restart server — ยืนยันด้วยการรัน
	// server จริงแล้วพบ wtrs_date/cdors_date หลุด NOT NULL, wtrs_set_no/wtrs_reps/
	// cdors_duration ถูกแปลงจาก tinyint/smallint unsigned เป็น bigint(20) เงียบๆ (ดู
	// docs/SPEC.md ข้อ 6 D10) เหตุผลเดียวกับที่ WorkoutSchedule ถูกถอดไปก่อนแล้ว (D3.2) — จัดการ schema
	// ผ่าน migration script เท่านั้น
	if err := DB.AutoMigrate(&models.RevokedToken{}, &models.AuditLog{}); err != nil {
		log.Printf("⚠️  AutoMigrate warning (security tables): %v", err)
	}

	fmt.Println("✅ Database connected successfully!")
}
