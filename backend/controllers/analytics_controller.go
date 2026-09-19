package controllers

import (
	"food_and_fit_api/helpers"
	"food_and_fit_api/services"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// GetDailyAnalytics - สรุปพลังงานและโภชนาการรายวัน
func GetDailyAnalytics(c *gin.Context) {
	userID, _ := c.Get("user_id")
	date := c.Query("date")
	if date == "" {
		date = time.Now().Format("2006-01-02")
	}

	result := services.GetDailyAnalyticsData(userID, date)
	c.JSON(http.StatusOK, result)
}

// GetWeeklyAnalytics - สรุปรายสัปดาห์ (7 วัน สิ้นสุดที่ ?date= หรือวันนี้ถ้าไม่ระบุ)
func GetWeeklyAnalytics(c *gin.Context) {
	userID, _ := c.Get("user_id")

	refDate := time.Now()
	if dateParam := c.Query("date"); dateParam != "" {
		parsed, err := time.Parse("2006-01-02", dateParam)
		if err != nil {
			helpers.RespondBadRequest(c, "date", "รูปแบบวันที่ไม่ถูกต้อง (ต้องเป็น YYYY-MM-DD)")
			return
		}
		if parsed.Format("2006-01-02") > time.Now().Format("2006-01-02") {
			helpers.RespondBadRequest(c, "date", "ไม่สามารถระบุวันที่ในอนาคตได้")
			return
		}
		refDate = parsed
	}
	// -6 เพื่อให้ช่วง [startDate, endDate] รวม endDate แล้วได้ 7 วันพอดี (ไม่ใช่ 8 วันแบบ dailySumRangeSQL เดิม)
	startDate := refDate.AddDate(0, 0, -6).Format("2006-01-02")
	endDate := refDate.Format("2006-01-02")

	results := services.GetDailySumBetween(userID, startDate, endDate)
	c.JSON(http.StatusOK, gin.H{"data": results})
}

// GetMonthlyAnalytics - สรุปรายเดือน (30 วันย้อนหลัง)
func GetMonthlyAnalytics(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var startDate, endDate string
	if monthParam := c.Query("month"); monthParam != "" {
		parsed, err := time.Parse("2006-01", monthParam)
		if err != nil {
			helpers.RespondBadRequest(c, "month", "รูปแบบเดือนไม่ถูกต้อง (ต้องเป็น YYYY-MM)")
			return
		}
		startDate = parsed.Format("2006-01-02")
		endDate = parsed.AddDate(0, 1, -1).Format("2006-01-02")
	} else {
		endDate = time.Now().Format("2006-01-02")
		startDate = time.Now().AddDate(0, 0, -30).Format("2006-01-02")
	}

	results := services.GetDailySumBetween(userID, startDate, endDate)
	c.JSON(http.StatusOK, gin.H{"data": results})
}

// GetProgressReport - รายงานความคืบหน้า (น้ำหนัก, พลังงานเฉลี่ย, จำนวนครั้งที่ซ้อม)
func GetProgressReport(c *gin.Context) {
	userID, _ := c.Get("user_id")
	days := c.DefaultQuery("days", "30")

	result := services.GetProgressReportData(userID, days)
	c.JSON(http.StatusOK, gin.H{
		"weight_change":    result.WeightChange,
		"calorie_avg":      result.CalorieAvg,
		"workout_count":    result.WorkoutCount,
		"progress_percent": result.ProgressPercent,
		"body_history":     result.BodyHistory,
	})
}

// GetDailyMealBreakdown - แบ่งอาหารตามมื้อ (1=เช้า 2=กลางวัน 3=เย็น 4=ว่าง)
func GetDailyMealBreakdown(c *gin.Context) {
	userID, _ := c.Get("user_id")
	date := c.Query("date")
	if date == "" {
		date = time.Now().Format("2006-01-02")
	}
	rows := services.GetDailyMealBreakdownData(userID, date)
	c.JSON(http.StatusOK, gin.H{"date": date, "meals": rows})
}

// Get1RMHistory - ประวัติ 1RM รายวัน สำหรับท่าฝึกที่ระบุ
func Get1RMHistory(c *gin.Context) {
	userID, _ := c.Get("user_id")
	wetID := c.Param("wet_id")
	days := c.DefaultQuery("days", "30")
	rows := services.Get1RMHistoryData(userID, wetID, days)
	c.JSON(http.StatusOK, gin.H{"wet_id": wetID, "data": rows})
}

// GetMonthlyComparison - เปรียบเทียบเดือนนี้ vs เดือนที่แล้ว
func GetMonthlyComparison(c *gin.Context) {
	userID, _ := c.Get("user_id")

	// เดือนที่จะเทียบ — รับจาก query ?month=YYYY-MM (เดือนที่ frontend กำลังเลื่อนดูอยู่)
	// ไม่ส่งมา = ใช้เดือนปัจจุบันจริงเหมือนเดิม (บั๊กเดิม: ไม่รับ param นี้เลย ใช้ CURDATE() เสมอ
	// ทำให้การ์ดนี้ไม่ผูกกับเดือนที่ผู้ใช้เลื่อนดูในกราฟ/ตารางด้านบน — พบจากทดสอบจริงบนเครื่อง 2026-08-21)
	refDate := ""
	if monthParam := c.Query("month"); monthParam != "" {
		parsed, err := time.Parse("2006-01", monthParam)
		if err != nil {
			helpers.RespondBadRequest(c, "month", "รูปแบบเดือนไม่ถูกต้อง (ต้องเป็น YYYY-MM)")
			return
		}
		refDate = parsed.Format("2006-01-02")
	}

	result := services.GetMonthlyComparisonData(userID, refDate)
	c.JSON(http.StatusOK, gin.H{
		"this_month":     gin.H{"avg_cal": result.ThisMonth.AvgCal, "workout_days": result.ThisMonth.WorkoutDays, "avg_cardio": result.ThisMonth.AvgCardio, "avg_weight": result.ThisMonth.AvgWeight, "recorded_days": result.ThisMonth.RecordedDays},
		"last_month":     gin.H{"avg_cal": result.LastMonth.AvgCal, "workout_days": result.LastMonth.WorkoutDays, "avg_cardio": result.LastMonth.AvgCardio, "avg_weight": result.LastMonth.AvgWeight, "recorded_days": result.LastMonth.RecordedDays},
		"cal_change_pct": result.CalChangePct,
		"workout_change": result.WorkoutChange,
	})
}

// GetMuscleGroupCoverage - กล้ามเนื้อที่ฝึกในช่วง N วัน
func GetMuscleGroupCoverage(c *gin.Context) {
	userID, _ := c.Get("user_id")
	days := c.DefaultQuery("days", "7")
	rows := services.GetMuscleGroupCoverageData(userID, days)
	c.JSON(http.StatusOK, gin.H{"days": days, "data": rows})
}

// ─────────────────────────────────────────────────────────────────────────────
// GetAdminAnalyticsOverview - สรุปข้อมูลภาพรวมสำหรับแอดมิน
// GET /api/admin/analytics/overview?start=YYYY-MM-DD&end=YYYY-MM-DD
// ─────────────────────────────────────────────────────────────────────────────
func GetAdminAnalyticsOverview(c *gin.Context) {
	now := time.Now()
	start := c.Query("start")
	end := c.Query("end")
	if start == "" {
		start = now.AddDate(0, -1, 0).Format("2006-01-02")
	}
	if end == "" {
		end = now.Format("2006-01-02")
	}

	result := services.GetAdminAnalyticsOverviewData(start, end)
	c.JSON(http.StatusOK, gin.H{
		"total_members":          result.TotalMembers,
		"new_members_total":      result.NewMembersTotal,
		"total_cal_in":           result.TotalCalIn,
		"total_cal_out":          result.TotalCalOut,
		"total_workouts":         result.TotalWorkouts,
		"weight_percent":         result.WeightPercent,
		"cardio_percent":         result.CardioPercent,
		"total_duration_minutes": result.TotalDurationMinutes,
		"chart_data":             result.ChartData,
		"weekly_data":            result.WeeklyData,
		"popular_menus":          result.PopularMenus,
	})
}
