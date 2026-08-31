package controllers

import (
	"net/http"
	"strings"

	"food_and_fit_api/config"
	"food_and_fit_api/models"
	"food_and_fit_api/utils"

	"github.com/gin-gonic/gin"
)

// endpoint ใหม่สำหรับ D1 (รายชื่อสมาชิก) + D2 (รายละเอียดสมาชิก) ฝั่ง Admin Web
// อ่านอย่างเดียว (read-only) ตามสเปก — ไม่มี endpoint แก้ไข/ลบสมาชิกในรอบนี้
// ไม่คืน mb_password_hash / mb_otp / mb_otp_expired เด็ดขาด (build gin.H เอง ไม่ dump struct ตรงๆ)
// ไม่กรอง mb_status ฝั่ง backend — คืนทุกสถานะ (ไม่มี filter ตาม status ฝั่งไหนเลย mb_status=2/
// mb_deleted_at ถูกถอดออกจากระบบไปแล้ว ห้าม re-add)
//
// member_profile ไม่มีคอลัมน์เบอร์โทร (ตรวจ models/member.go แล้ว มีแค่ mb_email) search จึง
// match แค่ชื่อ+อีเมล ไม่ใช่ "ชื่อ/อีเมล/เบอร์โทร" ตามที่ร่างสเปกไว้ (ยืนยันกับผู้ใช้แล้ว 2026-08-29)

func memberSummaryJSON(m models.Member) gin.H {
	return gin.H{
		"mb_id":          m.MbID,
		"mb_email":       m.MbEmail,
		"mb_full_name":   m.MbFullName,
		"mb_gender":      m.MbGender,
		"mb_birth_date":  m.MbBirthDate.Format("2006-01-02"),
		"mb_profile_pic": m.MbProfilePic,
		"mb_is_verified": m.MbIsVerified,
		"mb_status":      m.MbStatus,
		"mb_created_at":  m.MbCreatedAt.Format("2006-01-02 15:04:05"),
	}
}

// [FEATURE] PROFILE
// [FUNCTION] GetAllMembers
// [DESCRIPTION] ดึงรายชื่อสมาชิกแบบค้นหา+pagination ระดับ SQL สำหรับหน้ารายชื่อสมาชิกฝั่ง
//
//	Admin Web (ตารางข้อมูลโตไม่จำกัด ห้ามดึงทั้งหมดมากรองที่ Dart) — endpoint นี้
//	เป็น admin-only อยู่แล้ว (ไม่มีแอปมือถือเรียกใช้) แก้ query param ตรงๆ ได้
//
// [INPUT] query: search (match mb_full_name/mb_email), page, page_size
// [OUTPUT] {data: []Member (summary), total, page, page_size}
func GetAllMembers(c *gin.Context) {
	page, pageSize, offset := utils.ParsePagination(c)

	query := config.DB.Model(&models.Member{})
	if search := strings.TrimSpace(c.Query("search")); search != "" {
		like := "%" + search + "%"
		query = query.Where("mb_full_name LIKE ? OR mb_email LIKE ?", like, like)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "นับจำนวนสมาชิกไม่สำเร็จ"})
		return
	}

	var members []models.Member
	if err := query.Order("mb_created_at desc").Offset(offset).Limit(pageSize).Find(&members).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "โหลดรายชื่อสมาชิกไม่สำเร็จ"})
		return
	}

	data := make([]gin.H, 0, len(members))
	for _, m := range members {
		data = append(data, memberSummaryJSON(m))
	}

	c.JSON(http.StatusOK, gin.H{
		"data":      data,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// GetMemberDetail - GET /api/admin/members/:id
// คืนโปรไฟล์ + ประวัติร่างกาย (member_body_stats) + ประวัติ BMI/BMR/TDEE (member_bmr_history)
// ทั้งคู่เรียงใหม่สุดก่อน (record date DESC) ให้ frontend กลับลำดับเองถ้าต้องวาดกราฟ
func GetMemberDetail(c *gin.Context) {
	id := c.Param("id")

	var member models.Member
	if err := config.DB.First(&member, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูลสมาชิก"})
		return
	}

	var bodyStats []models.MemberBodyStat
	config.DB.Where("mb_id = ?", member.MbID).Order("mbs_recorded_date desc").Find(&bodyStats)

	bodyStatsJSON := make([]gin.H, 0, len(bodyStats))
	for _, s := range bodyStats {
		bodyStatsJSON = append(bodyStatsJSON, gin.H{
			"mbs_id":             s.MbsID,
			"mbs_weight":         s.MbsWeight,
			"mbs_height":         s.MbsHeight,
			"mbs_activity_level": s.MbsActivityLevel,
			"mbs_target":         s.MbsTarget,
			"mbs_recorded_date":  s.MbsRecordedDate.Format("2006-01-02 15:04:05"),
		})
	}

	var bmrHistory []models.MemberBmrHistory
	config.DB.Where("mb_id = ?", member.MbID).Order("mbh_record_date desc").Find(&bmrHistory)

	bmrHistoryJSON := make([]gin.H, 0, len(bmrHistory))
	for _, h := range bmrHistory {
		bmrHistoryJSON = append(bmrHistoryJSON, gin.H{
			"mbh_id":          h.MbhID,
			"mbh_record_date": h.MbhRecordDate.Format("2006-01-02"),
			"mbh_bmi":         h.MbhBmi,
			"mbh_bmr":         h.MbhBmr,
			"mbh_tdee":        h.MbhTdee,
			"mbh_tdee_target": h.MbhTdeeTarget,
		})
	}

	profile := memberSummaryJSON(member)

	c.JSON(http.StatusOK, gin.H{
		"profile":     profile,
		"body_stats":  bodyStatsJSON,
		"bmr_history": bmrHistoryJSON,
	})
}
