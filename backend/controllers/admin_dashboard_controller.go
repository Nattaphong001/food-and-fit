package controllers

import (
	"net/http"
	"time"

	"food_and_fit_api/config"

	"github.com/gin-gonic/gin"
)

// GetAdminDashboardSummary - GET /api/admin/dashboard/summary
// หน้า "ภาพรวมระบบ" (Dashboard) ฝั่ง Admin Web — หน้าที่คือ "สแกน 5 วินาทีแล้วรู้ว่าระบบปกติหรือไม่"
// จึงไม่มีตัวกรองช่วงเวลาให้ผู้ใช้เลือกเหมือนหน้ารายงาน (AdminReportView) — คำนวณช่วง 30 วันล่าสุด
// เทียบกับ 30 วันก่อนหน้าคงที่จากฝั่ง backend เพื่อสร้างเลข "เทียบกับช่วงก่อนหน้า" ในการ์ดสรุป
//
// เป็น endpoint ใหม่แยกจาก GetAdminAnalyticsOverview (หน้ารายงาน) ตามกฎห้ามแก้ endpoint เดิม
func GetAdminDashboardSummary(c *gin.Context) {
	now := time.Now()
	periodStart := now.AddDate(0, 0, -30).Format("2006-01-02")
	prevPeriodStart := now.AddDate(0, 0, -60).Format("2006-01-02")
	today := now.Format("2006-01-02")

	// 1. สมาชิกทั้งหมด (ตอนนี้) เทียบกับจำนวนที่ "น่าจะมี" เมื่อ 30 วันก่อน
	//    (สมาชิกที่สมัครก่อนวันเริ่มช่วงปัจจุบัน — ประมาณการ ไม่รวมผลของการลบระหว่างทาง)
	var totalMembersNow int64
	config.DB.Raw(`SELECT COUNT(*) FROM member_profile`).Scan(&totalMembersNow)

	var totalMembersPrev int64
	config.DB.Raw(`SELECT COUNT(*) FROM member_profile WHERE mb_created_at < ?`, periodStart).Scan(&totalMembersPrev)

	// 2. สมาชิกใหม่ในช่วง 30 วันล่าสุด เทียบกับ 30 วันก่อนหน้านั้น
	var newMembersNow int64
	config.DB.Raw(`SELECT COUNT(*) FROM member_profile WHERE mb_created_at BETWEEN ? AND ?`, periodStart, today).Scan(&newMembersNow)

	var newMembersPrev int64
	config.DB.Raw(`SELECT COUNT(*) FROM member_profile WHERE mb_created_at BETWEEN ? AND ?`, prevPeriodStart, periodStart).Scan(&newMembersPrev)

	// 3. ผู้ใช้ Active — มีบันทึกใน daily_nutrition หรือ weight_training_result หรือ cardio_result ในช่วงนั้น
	var activeNow int64
	config.DB.Raw(`
		SELECT COUNT(DISTINCT mb_id) FROM (
			SELECT mb_id FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?
			UNION
			SELECT mb_id FROM weight_training_result WHERE wtrs_date BETWEEN ? AND ?
			UNION
			SELECT mb_id FROM cardio_result WHERE cdors_date BETWEEN ? AND ?
		) t`, periodStart, today, periodStart, today, periodStart, today).Scan(&activeNow)

	var activePrev int64
	config.DB.Raw(`
		SELECT COUNT(DISTINCT mb_id) FROM (
			SELECT mb_id FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?
			UNION
			SELECT mb_id FROM weight_training_result WHERE wtrs_date BETWEEN ? AND ?
			UNION
			SELECT mb_id FROM cardio_result WHERE cdors_date BETWEEN ? AND ?
		) t`, prevPeriodStart, periodStart, prevPeriodStart, periodStart, prevPeriodStart, periodStart).Scan(&activePrev)

	// 4. อัตรายืนยันตัวตนสำเร็จ (ตอนนี้ vs ณ วันเริ่มช่วงปัจจุบัน)
	var verifiedNow int64
	config.DB.Raw(`SELECT COUNT(*) FROM member_profile WHERE mb_is_verified = 1`).Scan(&verifiedNow)

	var verifiedPrev int64
	config.DB.Raw(`SELECT COUNT(*) FROM member_profile WHERE mb_is_verified = 1 AND mb_created_at < ?`, periodStart).Scan(&verifiedPrev)

	verifiedRateNow := percentOf(verifiedNow, totalMembersNow)
	verifiedRatePrev := percentOf(verifiedPrev, totalMembersPrev)

	// 5. กราฟแท่งสมาชิกใหม่รายวัน ย้อนหลัง 30 วัน
	type RegPoint struct {
		Date  string `gorm:"column:date"  json:"date"`
		Count int    `gorm:"column:count" json:"count"`
	}
	var newMembersTimeline []RegPoint
	config.DB.Raw(`
		SELECT DATE(mb_created_at) AS date, COUNT(*) AS count
		FROM member_profile
		WHERE DATE(mb_created_at) BETWEEN ? AND ?
		GROUP BY DATE(mb_created_at)
		ORDER BY DATE(mb_created_at)
	`, periodStart, today).Scan(&newMembersTimeline)
	if newMembersTimeline == nil {
		newMembersTimeline = []RegPoint{}
	}

	// 6. สัดส่วนเป้าหมายสุขภาพ (1=ลดน้ำหนัก, 2=เพิ่มกล้ามเนื้อ, 3=รักษาน้ำหนัก) — นับจากค่าล่าสุดต่อสมาชิก
	type TargetCount struct {
		Target int `gorm:"column:mbs_target" json:"target"`
		Count  int `gorm:"column:count"      json:"count"`
	}
	var targetDistribution []TargetCount
	config.DB.Raw(`
		SELECT latest.mbs_target, COUNT(*) AS count
		FROM (
			SELECT mbs.mbs_target, mbs.mb_id
			FROM member_body_stats mbs
			INNER JOIN (SELECT mb_id, MAX(mbs_id) AS max_id FROM member_body_stats GROUP BY mb_id) top
				ON top.max_id = mbs.mbs_id
			INNER JOIN member_profile mp ON mp.mb_id = mbs.mb_id
		) latest
		GROUP BY latest.mbs_target
	`).Scan(&targetDistribution)
	if targetDistribution == nil {
		targetDistribution = []TargetCount{}
	}

	// 7. สมาชิกสมัครล่าสุด 8 แถว (สำหรับตารางท้ายหน้า Dashboard)
	type RecentMember struct {
		MbID       int    `gorm:"column:mb_id"         json:"mb_id"`
		FullName   string `gorm:"column:mb_full_name"  json:"mb_full_name"`
		CreatedAt  string `gorm:"column:mb_created_at" json:"mb_created_at"`
		IsVerified int    `gorm:"column:mb_is_verified" json:"mb_is_verified"`
	}
	var recentMembers []RecentMember
	config.DB.Raw(`
		SELECT mb_id, mb_full_name, mb_created_at, mb_is_verified
		FROM member_profile
		ORDER BY mb_created_at DESC
		LIMIT 8
	`).Scan(&recentMembers)
	if recentMembers == nil {
		recentMembers = []RecentMember{}
	}

	c.JSON(http.StatusOK, gin.H{
		"total_members":               totalMembersNow,
		"total_members_delta_percent": deltaPercent(totalMembersNow, totalMembersPrev),
		"new_members_total":           newMembersNow,
		"new_members_delta_percent":   deltaPercent(newMembersNow, newMembersPrev),
		"active_members":              activeNow,
		"active_members_delta_percent": deltaPercent(activeNow, activePrev),
		"verified_rate":               verifiedRateNow,
		"verified_rate_delta_point":   pointDelta(verifiedRateNow, verifiedRatePrev, totalMembersPrev),
		"new_members_timeline":        newMembersTimeline,
		"target_distribution":         targetDistribution,
		"recent_members":              recentMembers,
	})
}

// percentOf - เปอร์เซ็นต์ของ part จาก total ปลอดภัยจากการหารด้วยศูนย์ (คืน 0 แทน)
func percentOf(part, total int64) float64 {
	if total <= 0 {
		return 0
	}
	return float64(part) / float64(total) * 100
}

// deltaPercent - เปอร์เซ็นต์การเปลี่ยนแปลงจาก prev -> now, คืน nil เมื่อไม่มีฐานเทียบ (prev = 0)
// เพื่อให้ frontend แสดง "—" แทนเลข infinity/NaN ตามข้อกำหนดสถานะ "ไม่มีข้อมูล" ของการ์ดสรุป
func deltaPercent(now, prev int64) interface{} {
	if prev <= 0 {
		return nil
	}
	return float64(now-prev) / float64(prev) * 100
}

// pointDelta - ผลต่างแบบ percentage point ระหว่างอัตราปัจจุบันกับอัตราก่อนหน้า
// คืน nil เมื่อไม่มีฐานเทียบ (ยังไม่มีสมาชิกในช่วงก่อนหน้าเลย)
func pointDelta(now, prev float64, prevBase int64) interface{} {
	if prevBase <= 0 {
		return nil
	}
	return now - prev
}
