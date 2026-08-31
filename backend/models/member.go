package models

import (
	"time"
)

// MbStatus: 1=Active (ตรงกับ migrations/Datadic_updated.dart) — เดิมเคยมีค่า 2=Deleted
// สำหรับฟีเจอร์ "ลบบัญชี" แบบ Grace Period แต่ไม่เคยมี endpoint ไหน trigger จริง (ไม่มีทั้งฝั่ง
// มือถือและ admin web) จึงตัดออกทั้งระบบแล้ว (ดู CLAUDE.md หัวข้อ 4 D8)
const (
	MbStatusActive = 1
)

type Member struct {
	MbID           int        `gorm:"primaryKey;column:mb_id;autoIncrement"`
	MbEmail        string     `gorm:"column:mb_email;type:varchar(100)"`
	MbPasswordHash string     `gorm:"column:mb_password_hash;type:varchar(255)" json:"-"`
	MbFullName     string     `gorm:"column:mb_full_name;type:varchar(100)"`
	MbGender       int        `gorm:"column:mb_gender;type:tinyint"`
	MbBirthDate    time.Time  `gorm:"column:mb_birth_date;type:date"`
	MbProfilePic   string     `gorm:"column:mb_profile_pic;type:varchar(255)"`
	MbIsVerified   int        `gorm:"column:mb_is_verified;type:tinyint;default:0"`
	MbOtp          string     `gorm:"column:mb_otp;type:varchar(6)"`
	MbOtpExpired   *time.Time `gorm:"column:mb_otp_expired;type:datetime"`
	MbCreatedAt    time.Time  `gorm:"column:mb_created_at;autoCreateTime"`
	MbUpdatedAt    time.Time  `gorm:"column:mb_updated_at;autoUpdateTime"`
	MbStatus       int        `gorm:"column:mb_status;type:tinyint;default:1"`
	// แผนที่ใช้งานอยู่ตอนนี้ — มีค่าได้แค่ 1 ใน 2 (อีกอันเป็น NULL): wpt_id = แผนระบบ, mwp_id = แผนส่วนตัว
	MbActiveWptID *uint `gorm:"column:mb_active_wpt_id"`
	MbActiveMwpID *uint `gorm:"column:mb_active_mwp_id"`
}

type MemberBodyStat struct {
	MbsID            int       `gorm:"primaryKey;column:mbs_id;autoIncrement"`
	MbID             int       `gorm:"column:mb_id"`
	MbsWeight        float64   `gorm:"column:mbs_weight;type:decimal(5,2)"`
	MbsHeight        float64   `gorm:"column:mbs_height;type:decimal(5,2)"`
	MbsActivityLevel float64   `gorm:"column:mbs_activity_level;type:decimal(4,3)"`
	MbsTarget        int       `gorm:"column:mbs_target;type:tinyint"` // 1=ลดน้ำหนัก, 2=เพิ่มกล้ามเนื้อ, 3=รักษาน้ำหนัก
	MbsRecordedDate  time.Time `gorm:"column:mbs_recorded_date;type:datetime"`
}

type MemberBmrHistory struct {
	MbhID         int       `gorm:"primaryKey;column:mbh_id;autoIncrement"`
	MbID          int       `gorm:"column:mb_id"`
	MbsID         *int      `gorm:"column:mbs_id"`
	MbhRecordDate time.Time `gorm:"column:mbh_record_date;type:date"`
	MbhBmi        float64   `gorm:"column:mbh_bmi;type:decimal(4,2)"`
	MbhBmr        float64   `gorm:"column:mbh_bmr;type:decimal(7,2)"`
	MbhTdee       float64   `gorm:"column:mbh_tdee;type:decimal(7,2)"`
	MbhTdeeTarget float64   `gorm:"column:mbh_tdee_target;type:decimal(7,2)"`
}

func (Member) TableName() string           { return "member_profile" }
func (MemberBodyStat) TableName() string   { return "member_body_stats" }
func (MemberBmrHistory) TableName() string { return "member_bmr_history" }
