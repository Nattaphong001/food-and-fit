package config

import (
	"fmt"
	"log/slog"
	"net/url"
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
			slog.Warn(".env file not found, will use environment variables")
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
	dsn := buildDSN(dbUser, dbPass, dbHost, dbPort, dbName)

	slog.Info("connecting to database", "user", dbUser, "host", dbHost, "port", dbPort, "db", dbName)

	database, err := gorm.Open(mysql.Open(dsn), &gorm.Config{})
	if err != nil {
		slog.Error("failed to connect to database", "err", err)
		os.Exit(1)
	}

	// ตั้งค่า connection pool ป้องกัน "invalid connection"
	sqlDB, err := database.DB()
	if err != nil {
		slog.Error("failed to get sql.DB", "err", err)
		os.Exit(1)
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
	// cdors_duration ถูกแปลงจาก tinyint/smallint unsigned เป็น bigint(20) เงียบๆ —
	// เหตุผลเดียวกับที่ WorkoutSchedule ถูกถอดไปก่อนแล้ว — จัดการ schema
	// ผ่าน migration script เท่านั้น
	if err := DB.AutoMigrate(&models.RevokedToken{}, &models.AuditLog{}); err != nil {
		slog.Warn("AutoMigrate warning (security tables)", "err", err)
	}

	fmt.Println("✅ Database connected successfully!")
}

// sessionTimeZone - เขตเวลาของ session MySQL ต้องตรงกับเวลาของแอป (main.go ตั้ง time.Local = Asia/Bangkok, UTC+7)
// เพื่อให้ CURDATE()/NOW() ใน SQL (analytics_service.go) ได้วันที่เดียวกับที่ Go ใช้บันทึก wtrs_date/cdors_date
// แม้ย้าย DB ไปอยู่บนโฮสต์ที่ตั้งเขตเวลาเป็น UTC (ไม่ใส่ = ใช้ @@global.time_zone ของเซิร์ฟเวอร์ ซึ่ง XAMPP ปัจจุบันเป็น SYSTEM = +7)
const sessionTimeZone = "+07:00"

// buildDSN - timeout=30s ป้องกัน dial hang, parseTime + loc=Local (= Asia/Bangkok ตาม main.go) + time_zone ของ session
func buildDSN(user, pass, host, port, name string) string {
	return fmt.Sprintf(
		"%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local&timeout=30s&readTimeout=30s&writeTimeout=30s&time_zone=%s",
		user, pass, host, port, name, url.QueryEscape("'"+sessionTimeZone+"'"),
	)
}
