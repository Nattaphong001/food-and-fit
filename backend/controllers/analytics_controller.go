package controllers

import (
	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"
	"food_and_fit_api/services"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

// GetDailyAnalytics - สรุปแคลอรี่และโภชนาการรายวัน
func GetDailyAnalytics(c *gin.Context) {
	userID, _ := c.Get("user_id")
	date := c.Query("date")
	if date == "" {
		date = time.Now().Format("2006-01-02")
	}

	// 1. ดึงข้อมูล BMR/TDEE ที่ "มีผลใช้งานจริง ณ วันที่รายงาน" — แถวล่าสุดที่ mbh_record_date
	//    ไม่เกินวันที่ query (ไม่ใช่แถวล่าสุดสุดของทั้งระบบ) มิฉะนั้นรายงานย้อนหลังจะใช้
	//    BMR/TDEE ของวันนี้ไปคำนวณวันเก่าผิด — mbh_id desc เป็น tie-breaker กรณีแก้ไขวันเดียวกันหลายครั้ง
	var bmrHistory models.MemberBmrHistory
	config.DB.Where("mb_id = ? AND mbh_record_date <= ?", userID, date).
		Order("mbh_record_date desc, mbh_id desc").Limit(1).Find(&bmrHistory)

	isBmrEstimated := bmrHistory.MbhID == 0
	if isBmrEstimated {
		bmrHistory.MbhBmr = 1500
		bmrHistory.MbhTdee = 1800
		bmrHistory.MbhTdeeTarget = 2000
	}

	// 2. รวมแคลอรี่และสารอาหารที่กินเข้าไป (Calories In)
	var macros struct {
		TotalCal     float64 `gorm:"column:total_cal"`
		TotalProtein float64 `gorm:"column:total_protein"`
		TotalCarb    float64 `gorm:"column:total_carb"`
		TotalFat     float64 `gorm:"column:total_fat"`
	}
	config.DB.Model(&models.DailyNutrition{}).
		Select("COALESCE(SUM(dntt_total_calories), 0) as total_cal, COALESCE(SUM(dntt_total_protein), 0) as total_protein, COALESCE(SUM(dntt_total_carb), 0) as total_carb, COALESCE(SUM(dntt_total_fat), 0) as total_fat").
		Where("mb_id = ? AND dntt_date = ?", userID, date).
		Scan(&macros)

	// 3. รวมแคลอรี่จากคาร์ดิโอ
	var cardioOut struct{ Total float64 `gorm:"column:total"` }
	config.DB.Model(&models.CardioResult{}).
		Select("COALESCE(SUM(cdors_calories), 0) as total").
		Where("mb_id = ? AND cdors_date = ?", userID, date).
		Scan(&cardioOut)

	// 4. รวมแคลอรี่จาก Weight Training
	var weightOut struct{ Total float64 `gorm:"column:total"` }
	config.DB.Model(&models.WeightTrainingResult{}).
		Select("COALESCE(SUM(wtrs_calories), 0) as total").
		Where("mb_id = ? AND wtrs_date = ?", userID, date).
		Scan(&weightOut)

	// 5. ดึงข้อมูลน้ำหนัก เป้าหมาย สำหรับ Water Intake และ Goal Label — ดึงจากแถว member_body_stats
	//    ที่ bmrHistory ผูกไว้ตรงๆ (mbh.mbs_id) ให้ตรงกับ BMR/TDEE ของวันที่รายงานพอดี ไม่ใช่แถว
	//    ล่าสุดสุดของทั้งระบบซึ่งอาจเป็นคนละช่วงเวลากับ bmrHistory ที่เลือกไว้ข้างบน
	var bodyStat models.MemberBodyStat
	if bmrHistory.MbsID != nil {
		config.DB.Where("mbs_id = ?", *bmrHistory.MbsID).First(&bodyStat)
	}
	if bodyStat.MbsID == 0 {
		config.DB.Where("mb_id = ?", userID).Order("mbs_id desc").First(&bodyStat)
	}

	// 6. คำนวณ Total Daily Energy Output ตามสูตร:
	//    Baseline (BMR × 1.2) + Exercise Burn (Cardio + Weight Training)
	baseline := services.CalculateBaselineExpenditure(bmrHistory.MbhBmr)
	exerciseBurn := cardioOut.Total + weightOut.Total
	totalCalOut := baseline + exerciseBurn

	// 7. Balance = Energy In - Total Energy Out
	balance := macros.TotalCal - totalCalOut

	// 8. target_tdee — ใช้ค่าที่ CalculateGoals คำนวณและบันทึกไว้แล้วตอน UpdateBodyStats/
	//    UpdateProfile (mbh_tdee_target) ตรงๆ ไม่คำนวณซ้ำมือที่นี่ (เดิมเขียนสูตร 20%/15%/clamp
	//    ซ้ำอีกจุดหนึ่ง เสี่ยงเพี้ยนจาก services.CalculateGoals ถ้าแก้ % แค่จุดเดียว)
	targetTdee := bmrHistory.MbhTdeeTarget

	c.JSON(http.StatusOK, gin.H{
		"date":               date,
		"bmi":                bmrHistory.MbhBmi,
		"bmr":                bmrHistory.MbhBmr,
		"tdee":               bmrHistory.MbhTdee,
		"is_bmr_estimated":   isBmrEstimated,
		"target_tdee":        targetTdee,
		"weight":             bodyStat.MbsWeight,
		"goal_type":          bodyStat.MbsTarget,
		"total_calories_in":  macros.TotalCal,
		"total_calories_out": totalCalOut,
		"baseline":           baseline,
		"exercise_burn":      exerciseBurn,
		"balance":            balance,
		"macros": gin.H{
			"total_protein": macros.TotalProtein,
			"total_carbs":   macros.TotalCarb,
			"total_fat":     macros.TotalFat,
		},
	})
}

// DailySum - แถวสรุปรายวันสำหรับ weekly/monthly analytics
type DailySum struct {
	Date        string  `json:"date"`
	CaloriesIn  float64 `json:"calories_in"`
	CaloriesOut float64 `json:"calories_out"`
	CardioOut   float64 `json:"cardio_out"`
	WeightOut   float64 `json:"weight_out"`
	Protein     float64 `json:"protein"`
	Carbs       float64 `json:"carbs"`
	Fat         float64 `json:"fat"`
	TargetTdee  float64 `json:"target_tdee"` // เป้าหมายที่มีผลใช้งานจริง ณ วันนั้น (ไม่ใช่เป้าหมายปัจจุบัน) ให้กราฟสลับเส้นตรงวันที่เปลี่ยนเป้าหมายได้จริง
}

// dailySumRangeSQL - ใช้ร่วมกันระหว่าง weekly/monthly analytics
// ลำดับพารามิเตอร์: baseline, mb_id(x3 ใน date_list), mb_id(x3 ใน join), days
const dailySumRangeSQL = `
	SELECT date_list.date,
		   COALESCE(SUM(dn.dntt_total_calories), 0) as calories_in,
		   ? + COALESCE(cr_sum.total_out, 0) + COALESCE(wt_sum.total_out, 0) as calories_out,
		   COALESCE(cr_sum.total_out, 0) as cardio_out,
		   COALESCE(wt_sum.total_out, 0) as weight_out,
		   COALESCE(SUM(dn.dntt_total_protein), 0) as protein,
		   COALESCE(SUM(dn.dntt_total_carb), 0) as carbs,
		   COALESCE(SUM(dn.dntt_total_fat), 0) as fat
	FROM (
		SELECT DISTINCT dntt_date as date FROM daily_nutrition WHERE mb_id = ?
		UNION
		SELECT DISTINCT cdors_date as date FROM cardio_result WHERE mb_id = ?
		UNION
		SELECT DISTINCT wtrs_date as date FROM weight_training_result WHERE mb_id = ?
	) as date_list
	LEFT JOIN daily_nutrition dn ON dn.dntt_date = date_list.date AND dn.mb_id = ?
	LEFT JOIN (
		SELECT cdors_date, SUM(cdors_calories) as total_out
		FROM cardio_result WHERE mb_id = ? GROUP BY cdors_date
	) cr_sum ON cr_sum.cdors_date = date_list.date
	LEFT JOIN (
		SELECT wtrs_date, SUM(wtrs_calories) as total_out
		FROM weight_training_result WHERE mb_id = ? GROUP BY wtrs_date
	) wt_sum ON wt_sum.wtrs_date = date_list.date
	WHERE date_list.date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
	GROUP BY date_list.date
	ORDER BY date_list.date ASC
`

// dailySumBetweenSQL - เหมือน dailySumRangeSQL แต่กรองด้วยช่วงวันที่ระบุตรงๆ (ใช้กับ monthly ที่เลือกเดือนได้)
// baseline (BMR×1.2) และ target_tdee คำนวณต่อวันจาก member_bmr_history แถวที่ "มีผลใช้งานจริง
// ณ วันนั้น" (mbh_record_date ล่าสุดที่ไม่เกิน date_list.date) แทนค่าคงที่ค่าเดียวแบบเดิม —
// เดิมส่ง baseline เป็น parameter ตัวเลขเดียวคำนวณจาก BMR ล่าสุดสุด ทำให้ทุกวันในรายงานใช้ BMR
// ของวันนี้ผิดๆ ถ้าผู้ใช้เพิ่งแก้น้ำหนัก/เป้าหมายเปลี่ยนกลางช่วงที่รายงาน
// ลำดับพารามิเตอร์: mb_id(baseline subquery), mb_id(target subquery), mb_id(x3 ใน date_list),
//                    mb_id(join dn), mb_id(cr_sum), mb_id(wt_sum), startDate, endDate
const dailySumBetweenSQL = `
	SELECT date_list.date,
		   COALESCE(SUM(dn.dntt_total_calories), 0) as calories_in,
		   (COALESCE((SELECT mbh.mbh_bmr FROM member_bmr_history mbh
		              WHERE mbh.mb_id = ? AND mbh.mbh_record_date <= date_list.date
		              ORDER BY mbh.mbh_record_date DESC, mbh.mbh_id DESC LIMIT 1), 1500) * 1.2)
		     + COALESCE(cr_sum.total_out, 0) + COALESCE(wt_sum.total_out, 0) as calories_out,
		   COALESCE(cr_sum.total_out, 0) as cardio_out,
		   COALESCE(wt_sum.total_out, 0) as weight_out,
		   COALESCE(SUM(dn.dntt_total_protein), 0) as protein,
		   COALESCE(SUM(dn.dntt_total_carb), 0) as carbs,
		   COALESCE(SUM(dn.dntt_total_fat), 0) as fat,
		   COALESCE((SELECT mbh.mbh_tdee_target FROM member_bmr_history mbh
		             WHERE mbh.mb_id = ? AND mbh.mbh_record_date <= date_list.date
		             ORDER BY mbh.mbh_record_date DESC, mbh.mbh_id DESC LIMIT 1), 2000) as target_tdee
	FROM (
		SELECT DISTINCT dntt_date as date FROM daily_nutrition WHERE mb_id = ?
		UNION
		SELECT DISTINCT cdors_date as date FROM cardio_result WHERE mb_id = ?
		UNION
		SELECT DISTINCT wtrs_date as date FROM weight_training_result WHERE mb_id = ?
	) as date_list
	LEFT JOIN daily_nutrition dn ON dn.dntt_date = date_list.date AND dn.mb_id = ?
	LEFT JOIN (
		SELECT cdors_date, SUM(cdors_calories) as total_out
		FROM cardio_result WHERE mb_id = ? GROUP BY cdors_date
	) cr_sum ON cr_sum.cdors_date = date_list.date
	LEFT JOIN (
		SELECT wtrs_date, SUM(wtrs_calories) as total_out
		FROM weight_training_result WHERE mb_id = ? GROUP BY wtrs_date
	) wt_sum ON wt_sum.wtrs_date = date_list.date
	WHERE date_list.date BETWEEN ? AND ?
	GROUP BY date_list.date
	ORDER BY date_list.date ASC
`

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

	var results []DailySum
	config.DB.Raw(dailySumBetweenSQL,
		userID, userID, userID, userID, userID, userID, userID, userID, startDate, endDate,
	).Scan(&results)

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

	var results []DailySum
	config.DB.Raw(dailySumBetweenSQL,
		userID, userID, userID, userID, userID, userID, userID, userID, startDate, endDate,
	).Scan(&results)

	c.JSON(http.StatusOK, gin.H{"data": results})
}

// GetProgressReport - รายงานความคืบหน้า (น้ำหนัก, แคลอรี่เฉลี่ย, จำนวนครั้งที่ซ้อม)
func GetProgressReport(c *gin.Context) {
	userID, _ := c.Get("user_id")
	days := c.DefaultQuery("days", "30")

	// 1. ประวัติน้ำหนักและ BMI — ใส่ activity_level/target ต่อจุดด้วย ให้ frontend detect วันที่
	//    ผู้ใช้เปลี่ยนระดับกิจกรรม/เป้าหมาย เพื่อ mark จุดเปลี่ยนบนกราฟได้ (ไม่ใช่แค่เส้นเดียวลากยาว)
	type BodyPoint struct {
		Date          string  `json:"date"`
		Weight        float64 `json:"weight"`
		Bmi           float64 `json:"bmi"`
		ActivityLevel float64 `json:"activity_level"`
		Target        int     `json:"target"`
	}
	var bodyHistory []BodyPoint
	// เดิมดึงทุกแถว member_body_stats ในช่วง — ถ้าแก้ข้อมูลร่างกายหลายครั้งในวันเดียว (เช่น
	// กรอกทดสอบแล้วแก้กลับ) จะได้หลายจุดซ้อนวันเดียวกัน กราฟกระโดด (spike) ไม่สื่อความหมาย
	// mbs_recorded_date ตั้งใจให้ 1 แถวประวัติแทน 1 วัน (ฝั่งรายงาน BMR/TDEE ก็ยึดหลักนี้อยู่แล้ว
	// ที่ dailySumBetweenSQL) จึงเลือกแถวล่าสุด (mbs_id มากสุด) ของแต่ละวันปฏิทินมาแสดงจุดเดียว
	config.DB.Raw(`
		SELECT bs.mbs_recorded_date as date, bs.mbs_weight as weight,
			COALESCE(bh.mbh_bmi, 0) as bmi,
			bs.mbs_activity_level as activity_level,
			bs.mbs_target as target
		FROM member_body_stats bs
		JOIN (
			SELECT DATE(mbs_recorded_date) as d, MAX(mbs_id) as mbs_id
			FROM member_body_stats
			WHERE mb_id = ? AND mbs_recorded_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
			GROUP BY DATE(mbs_recorded_date)
		) latest ON latest.mbs_id = bs.mbs_id
		LEFT JOIN member_bmr_history bh ON bs.mbs_id = bh.mbs_id
		ORDER BY bs.mbs_recorded_date ASC
	`, userID, days).Scan(&bodyHistory)

	weightChange := 0.0
	if len(bodyHistory) >= 2 {
		weightChange = bodyHistory[len(bodyHistory)-1].Weight - bodyHistory[0].Weight
	}

	// 2. แคลอรี่ที่กินเข้าไปเฉลี่ยต่อวัน
	var avgCal struct{ Avg float64 }
	config.DB.Raw(`
		SELECT COALESCE(AVG(daily_total), 0) as avg FROM (
			SELECT SUM(dntt_total_calories) as daily_total
			FROM daily_nutrition
			WHERE mb_id = ? AND dntt_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
			GROUP BY dntt_date
		) t
	`, userID, days).Scan(&avgCal)

	// 3. จำนวนครั้งที่เล่น Weight Training
	var workoutCount struct{ Count int }
	config.DB.Raw(`
		SELECT COUNT(DISTINCT wtrs_date) as count FROM weight_training_result
		WHERE mb_id = ? AND wtrs_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
	`, userID, days).Scan(&workoutCount)

	// 4. คำนวณเปอร์เซ็นต์ความคืบหน้า (อ้างอิงเป้าหมาย 3 วัน/สัปดาห์)
	daysInt, _ := strconv.Atoi(days)
	if daysInt <= 0 {
		daysInt = 30
	}

	targetWorkouts := (daysInt / 7) * 3
	progressPercent := 0.0
	if targetWorkouts > 0 {
		progressPercent = (float64(workoutCount.Count) / float64(targetWorkouts)) * 100
		if progressPercent > 100 {
			progressPercent = 100
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"weight_change":    weightChange,
		"calorie_avg":      avgCal.Avg,
		"workout_count":    workoutCount.Count,
		"progress_percent": progressPercent,
		"body_history":     bodyHistory,
	})
}

// GetDailyMealBreakdown - แบ่งอาหารตามมื้อ (1=เช้า 2=กลางวัน 3=เย็น 4=ว่าง)
func GetDailyMealBreakdown(c *gin.Context) {
	userID, _ := c.Get("user_id")
	date := c.Query("date")
	if date == "" {
		date = time.Now().Format("2006-01-02")
	}
	type MealRow struct {
		MealType int     `gorm:"column:meal_type" json:"meal_type"`
		Calories float64 `gorm:"column:calories"  json:"calories"`
		Protein  float64 `gorm:"column:protein"   json:"protein"`
		Carbs    float64 `gorm:"column:carbs"     json:"carbs"`
		Fat      float64 `gorm:"column:fat"       json:"fat"`
		Count    int     `gorm:"column:count"     json:"count"`
	}
	var rows []MealRow
	config.DB.Raw(`
		SELECT dntt_meal_type as meal_type,
		       COALESCE(SUM(dntt_total_calories),0) as calories,
		       COALESCE(SUM(dntt_total_protein),0)  as protein,
		       COALESCE(SUM(dntt_total_carb),0)     as carbs,
		       COALESCE(SUM(dntt_total_fat),0)       as fat,
		       COUNT(*) as count
		FROM daily_nutrition
		WHERE mb_id = ? AND dntt_date = ?
		GROUP BY dntt_meal_type
		ORDER BY dntt_meal_type ASC
	`, userID, date).Scan(&rows)
	c.JSON(http.StatusOK, gin.H{"date": date, "meals": rows})
}

// Get1RMHistory - ประวัติ 1RM รายวัน สำหรับท่าฝึกที่ระบุ
func Get1RMHistory(c *gin.Context) {
	userID, _ := c.Get("user_id")
	wetID := c.Param("wet_id")
	days := c.DefaultQuery("days", "30")
	type RMPoint struct {
		Date      string  `gorm:"column:date"       json:"date"`
		Best1RM   float64 `gorm:"column:best_1rm"   json:"best_1rm"`
		BestWeight float64 `gorm:"column:best_weight" json:"best_weight"`
		BestReps  int     `gorm:"column:best_reps"  json:"best_reps"`
	}
	var rows []RMPoint
	config.DB.Raw(`
		SELECT wtrs_date as date,
		       MAX(wtrs_weight * (1 + wtrs_reps / 30.0)) as best_1rm,
		       SUBSTRING_INDEX(GROUP_CONCAT(wtrs_weight ORDER BY wtrs_weight*(1+wtrs_reps/30.0) DESC),',',1)+0 as best_weight,
		       CAST(SUBSTRING_INDEX(GROUP_CONCAT(wtrs_reps ORDER BY wtrs_weight*(1+wtrs_reps/30.0) DESC),',',1) AS UNSIGNED) as best_reps
		FROM weight_training_result
		WHERE mb_id = ? AND wet_id = ? AND wtrs_weight > 0 AND wtrs_reps > 0
		  AND wtrs_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
		GROUP BY wtrs_date
		ORDER BY wtrs_date ASC
	`, userID, wetID, days).Scan(&rows)
	c.JSON(http.StatusOK, gin.H{"wet_id": wetID, "data": rows})
}

// GetMonthlyComparison - เปรียบเทียบเดือนนี้ vs เดือนที่แล้ว
func GetMonthlyComparison(c *gin.Context) {
	userID, _ := c.Get("user_id")
	type MonthStat struct {
		AvgCal       float64 `gorm:"column:avg_cal"`
		WorkoutDays  int     `gorm:"column:workout_days"`
		AvgCardio    float64 `gorm:"column:avg_cardio"`
		AvgWeight    float64 `gorm:"column:avg_weight"`
		RecordedDays int     `gorm:"column:recorded_days"` // จำนวนวันที่มีบันทึกอาหารจริงในช่วง — คำสั่งที่ 19.2 (avg_cal หารด้วยตัวนี้ ไม่ใช่จำนวนวันปฏิทิน)
	}
	queryMonthStat := func(startExpr, endExpr string) MonthStat {
		var s MonthStat
		config.DB.Raw(`
			SELECT
			  COALESCE((SELECT AVG(daily_total) FROM (
			    SELECT SUM(dntt_total_calories) as daily_total
			    FROM daily_nutrition WHERE mb_id = ? AND dntt_date BETWEEN `+startExpr+` AND `+endExpr+`
			    GROUP BY dntt_date) t), 0) as avg_cal,
			  COALESCE((SELECT COUNT(DISTINCT wtrs_date) FROM weight_training_result
			    WHERE mb_id = ? AND wtrs_date BETWEEN `+startExpr+` AND `+endExpr+`), 0) as workout_days,
			  COALESCE((SELECT AVG(daily_c) FROM (
			    SELECT SUM(cdors_calories) as daily_c FROM cardio_result
			    WHERE mb_id = ? AND cdors_date BETWEEN `+startExpr+` AND `+endExpr+`
			    GROUP BY cdors_date) t), 0) as avg_cardio,
			  COALESCE((SELECT AVG(daily_w) FROM (
			    SELECT SUM(wtrs_calories) as daily_w FROM weight_training_result
			    WHERE mb_id = ? AND wtrs_date BETWEEN `+startExpr+` AND `+endExpr+`
			    GROUP BY wtrs_date) t), 0) as avg_weight,
			  COALESCE((SELECT COUNT(DISTINCT dntt_date) FROM daily_nutrition
			    WHERE mb_id = ? AND dntt_date BETWEEN `+startExpr+` AND `+endExpr+`), 0) as recorded_days
		`, userID, userID, userID, userID, userID).Scan(&s)
		return s
	}
	// เดือนที่จะเทียบ — รับจาก query ?month=YYYY-MM (เดือนที่ frontend กำลังเลื่อนดูอยู่)
	// ไม่ส่งมา = ใช้เดือนปัจจุบันจริงเหมือนเดิม (บั๊กเดิม: ไม่รับ param นี้เลย ใช้ CURDATE() เสมอ
	// ทำให้การ์ดนี้ไม่ผูกกับเดือนที่ผู้ใช้เลื่อนดูในกราฟ/ตารางด้านบน — พบจากทดสอบจริงบนเครื่อง 2026-08-21)
	var refDateExpr string
	if monthParam := c.Query("month"); monthParam != "" {
		parsed, err := time.Parse("2006-01", monthParam)
		if err != nil {
			helpers.RespondBadRequest(c, "month", "รูปแบบเดือนไม่ถูกต้อง (ต้องเป็น YYYY-MM)")
			return
		}
		refDateExpr = "'" + parsed.Format("2006-01-02") + "'"
	} else {
		refDateExpr = "CURDATE()"
	}
	thisMonth := queryMonthStat("DATE_FORMAT("+refDateExpr+",'%Y-%m-01')", "LAST_DAY("+refDateExpr+")")
	lastMonth := queryMonthStat("DATE_FORMAT(DATE_SUB("+refDateExpr+",INTERVAL 1 MONTH),'%Y-%m-01')",
		"LAST_DAY(DATE_SUB("+refDateExpr+",INTERVAL 1 MONTH))")

	calChangePct := 0.0
	if lastMonth.AvgCal > 0 {
		calChangePct = (thisMonth.AvgCal - lastMonth.AvgCal) / lastMonth.AvgCal * 100
	}
	c.JSON(http.StatusOK, gin.H{
		"this_month":      gin.H{"avg_cal": thisMonth.AvgCal, "workout_days": thisMonth.WorkoutDays, "avg_cardio": thisMonth.AvgCardio, "avg_weight": thisMonth.AvgWeight, "recorded_days": thisMonth.RecordedDays},
		"last_month":      gin.H{"avg_cal": lastMonth.AvgCal, "workout_days": lastMonth.WorkoutDays, "avg_cardio": lastMonth.AvgCardio, "avg_weight": lastMonth.AvgWeight, "recorded_days": lastMonth.RecordedDays},
		"cal_change_pct":  calChangePct,
		"workout_change":  thisMonth.WorkoutDays - lastMonth.WorkoutDays,
	})
}

// GetMuscleGroupCoverage - กล้ามเนื้อที่ฝึกในช่วง N วัน
func GetMuscleGroupCoverage(c *gin.Context) {
	userID, _ := c.Get("user_id")
	days := c.DefaultQuery("days", "7")
	type CoverageRow struct {
		MugID       uint   `gorm:"column:mug_id"       json:"mug_id"`
		MugName     string `gorm:"column:mug_name"     json:"mug_name"`
		MugZone     int8   `gorm:"column:mug_zone"     json:"mug_zone"`
		TrainedDays int    `gorm:"column:trained_days" json:"trained_days"`
		LastTrained string `gorm:"column:last_trained" json:"last_trained"`
	}
	var rows []CoverageRow
	config.DB.Raw(`
		SELECT mg.mug_id, mg.mug_name, mg.mug_zone,
		       COUNT(DISTINCT wtr.wtrs_date) as trained_days,
		       MAX(wtr.wtrs_date) as last_trained
		FROM weight_training_result wtr
		JOIN exercise_muscle_details emd ON emd.wet_id = wtr.wet_id
		JOIN muscle_group mg ON mg.mug_id = emd.mug_id
		WHERE wtr.mb_id = ? AND wtr.wtrs_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
		GROUP BY mg.mug_id, mg.mug_name, mg.mug_zone
		ORDER BY trained_days DESC
	`, userID, days).Scan(&rows)
	c.JSON(http.StatusOK, gin.H{"days": days, "data": rows})
}

// ─────────────────────────────────────────────────────────────────────────────
// GetAdminAnalyticsOverview - สรุปข้อมูลภาพรวมสำหรับแอดมิน
// GET /api/admin/analytics/overview?start=YYYY-MM-DD&end=YYYY-MM-DD
// ─────────────────────────────────────────────────────────────────────────────
func GetAdminAnalyticsOverview(c *gin.Context) {
	now := time.Now()
	start := c.Query("start")
	end   := c.Query("end")
	if start == "" {
		start = now.AddDate(0, -1, 0).Format("2006-01-02")
	}
	if end == "" {
		end = now.Format("2006-01-02")
	}

	// 1. จำนวนสมาชิกทั้งหมด
	var totalMembers int64
	config.DB.Raw("SELECT COUNT(*) FROM member_profile").Scan(&totalMembers)

	// 2. แคลอรี่เข้า (รวมทุกคน ในช่วง start–end)
	var calIn struct{ Total float64 }
	config.DB.Raw(`SELECT COALESCE(SUM(dntt_total_calories), 0) as total
		FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?`, start, end).Scan(&calIn)

	// 3. แคลอรี่ออก (Baseline BMR×1.2 ต่อวันที่มีกิจกรรม + คาร์ดิโอ + เวท) — ให้ตรงนิยาม
	//    Total Daily Energy Output เดียวกับ GetDailyAnalytics (ข้อ 6 ด้านบน) ไม่ใช่แค่ผลรวม
	//    exercise burn เฉยๆ เหมือนโค้ดเดิม (เคยขาด baseline ทำให้ตัวเลขแอดมินต่ำกว่าจริง)
	var cardioCalOut struct{ Total float64 }
	config.DB.Raw(`SELECT COALESCE(SUM(cdors_calories), 0) as total
		FROM cardio_result WHERE cdors_date BETWEEN ? AND ?`, start, end).Scan(&cardioCalOut)

	var weightCalOut struct{ Total float64 }
	config.DB.Raw(`SELECT COALESCE(SUM(wtrs_calories), 0) as total
		FROM weight_training_result WHERE wtrs_date BETWEEN ? AND ?`, start, end).Scan(&weightCalOut)

	// Baseline รวมทุกคน = Σ (CalculateBaselineExpenditure(BMR ล่าสุดของสมาชิก) × จำนวนวันที่มีกิจกรรมในช่วง)
	// BMR ล่าสุด fallback เป็น 1500 เมื่อสมาชิกไม่เคยมี member_bmr_history เลย ตรงกับค่า fallback
	// เดียวกับ GetDailyAnalytics (isBmrEstimated)
	type memberBaselineRow struct {
		MbID uint    `gorm:"column:mb_id"`
		Days int64   `gorm:"column:days"`
		Bmr  float64 `gorm:"column:bmr"`
	}
	var baselineRows []memberBaselineRow
	config.DB.Raw(`
		SELECT active.mb_id, active.days,
		       COALESCE((SELECT mbh_bmr FROM member_bmr_history mbh2
		                 WHERE mbh2.mb_id = active.mb_id
		                 ORDER BY mbh2.mbh_id DESC LIMIT 1), 1500) AS bmr
		FROM (
			SELECT mb_id, COUNT(DISTINCT date) AS days FROM (
				SELECT mb_id, dntt_date AS date FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?
				UNION
				SELECT mb_id, cdors_date AS date FROM cardio_result WHERE cdors_date BETWEEN ? AND ?
				UNION
				SELECT mb_id, wtrs_date AS date FROM weight_training_result WHERE wtrs_date BETWEEN ? AND ?
			) all_days
			GROUP BY mb_id
		) active
	`, start, end, start, end, start, end).Scan(&baselineRows)

	var baselineTotal float64
	for _, row := range baselineRows {
		baselineTotal += services.CalculateBaselineExpenditure(row.Bmr) * float64(row.Days)
	}

	totalCalOut := baselineTotal + cardioCalOut.Total + weightCalOut.Total

	// 4. จำนวน session การฝึก
	var weightSessions struct{ Count int64 }
	config.DB.Raw(`SELECT COUNT(*) as count FROM (
		SELECT DISTINCT mb_id, wtrs_date FROM weight_training_result
		WHERE wtrs_date BETWEEN ? AND ?) t`, start, end).Scan(&weightSessions)

	// นับแบบ DISTINCT mb_id+date เหมือน weightSessions ด้านบน — เดิมนับ COUNT(*) ตรงๆ ทำให้ถ้า
	// สมาชิกคนเดียวบันทึกคาร์ดิโอหลายครั้งในวันเดียว จะถูกนับเป็นหลาย "ครั้ง" ขณะที่เวทยกกี่เซ็ต
	// ในวันเดียวก็นับ 1 ครั้ง ทำให้วงกลมสัดส่วน weight/cardio เทียบกันคนละหน่วย
	var cardioSessions struct{ Count int64 }
	config.DB.Raw(`SELECT COUNT(*) as count FROM (
		SELECT DISTINCT mb_id, cdors_date FROM cardio_result
		WHERE cdors_date BETWEEN ? AND ?) t`, start, end).Scan(&cardioSessions)

	totalWorkouts := weightSessions.Count + cardioSessions.Count
	// ฐานของ weight_percent/cardio_percent คือ "จำนวนครั้งที่บันทึก" (session count) ไม่ใช่แคลอรี่
	// หรือเวลา — เจตนา เพราะ weight_training_result ไม่มีฟิลด์เวลา (ดูข้อ 5 ด้านล่าง totalDuration
	// นับเฉพาะคาร์ดิโอ) จึงไม่มีฐานเวลาที่ใช้เทียบทั้งสองประเภทกิจกรรมได้ session count เป็นค่าเดียว
	// ที่มีครบทั้งคู่โดยไม่ต้องพึ่งฟิลด์ที่ขาด
	weightPercent, cardioPercent := 0.0, 0.0
	if totalWorkouts > 0 {
		weightPercent = float64(weightSessions.Count) / float64(totalWorkouts) * 100
		cardioPercent = float64(cardioSessions.Count) / float64(totalWorkouts) * 100
	}

	// 5. เวลาออกกำลังกายรวม (นาที) จากคาร์ดิโอ
	var totalDuration struct{ Total int64 }
	config.DB.Raw(`SELECT COALESCE(SUM(cdors_duration), 0) as total
		FROM cardio_result WHERE cdors_date BETWEEN ? AND ?`, start, end).Scan(&totalDuration)

	// 6. Chart data (รายวัน)
	// calories_out = คาร์ดิโอ + เวท (Exercise Burn เต็มนิยาม บทที่ 2 หัวข้อ 2.1.4.6) — เดิมนับ
	// แค่คาร์ดิโอ ทำให้กราฟไม่รวมพลังงานจากเวทเทรนนิ่งเลย
	type DayPoint struct {
		Date        string  `gorm:"column:date" json:"date"`
		CaloriesIn  float64 `gorm:"column:calories_in" json:"calories_in"`
		CaloriesOut float64 `gorm:"column:calories_out" json:"calories_out"`
	}
	var chartData []DayPoint
	config.DB.Raw(`
		SELECT DATE_FORMAT(d.date, '%Y-%m-%d') AS date,
		       COALESCE(ni.cal_in,  0) AS calories_in,
		       COALESCE(co.cal_out, 0) + COALESCE(wo.weight_out, 0) AS calories_out
		FROM (
		  SELECT dntt_date AS date FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?
		  UNION
		  SELECT cdors_date FROM cardio_result WHERE cdors_date BETWEEN ? AND ?
		  UNION
		  SELECT wtrs_date FROM weight_training_result WHERE wtrs_date BETWEEN ? AND ?
		) d
		LEFT JOIN (
		  SELECT dntt_date, SUM(dntt_total_calories) AS cal_in
		  FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?
		  GROUP BY dntt_date
		) ni ON ni.dntt_date = d.date
		LEFT JOIN (
		  SELECT cdors_date, SUM(cdors_calories) AS cal_out
		  FROM cardio_result WHERE cdors_date BETWEEN ? AND ?
		  GROUP BY cdors_date
		) co ON co.cdors_date = d.date
		LEFT JOIN (
		  SELECT wtrs_date, SUM(wtrs_calories) AS weight_out
		  FROM weight_training_result WHERE wtrs_date BETWEEN ? AND ?
		  GROUP BY wtrs_date
		) wo ON wo.wtrs_date = d.date
		ORDER BY d.date`,
		start, end, start, end, start, end, start, end, start, end, start, end,
	).Scan(&chartData)

	// 7. Weekly data — cal_out นับคาร์ดิโอ+เวทเช่นเดียวกับ chart_data ด้านบน
	type WeekPoint struct {
		Label  string  `gorm:"column:label" json:"label"`
		CalIn  float64 `gorm:"column:cal_in" json:"cal_in"`
		CalOut float64 `gorm:"column:cal_out" json:"cal_out"`
	}
	var weeklyData []WeekPoint
	config.DB.Raw(`
		SELECT DATE_FORMAT(MIN(d.date), '%d/%m') AS label,
		       COALESCE(SUM(ni.cal_in),  0) AS cal_in,
		       COALESCE(SUM(co.cal_out), 0) + COALESCE(SUM(wo.weight_out), 0) AS cal_out
		FROM (
		  SELECT dntt_date AS date FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?
		  UNION
		  SELECT cdors_date FROM cardio_result WHERE cdors_date BETWEEN ? AND ?
		  UNION
		  SELECT wtrs_date FROM weight_training_result WHERE wtrs_date BETWEEN ? AND ?
		) d
		LEFT JOIN (
		  SELECT dntt_date, SUM(dntt_total_calories) AS cal_in
		  FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?
		  GROUP BY dntt_date
		) ni ON ni.dntt_date = d.date
		LEFT JOIN (
		  SELECT cdors_date, SUM(cdors_calories) AS cal_out
		  FROM cardio_result WHERE cdors_date BETWEEN ? AND ?
		  GROUP BY cdors_date
		) co ON co.cdors_date = d.date
		LEFT JOIN (
		  SELECT wtrs_date, SUM(wtrs_calories) AS weight_out
		  FROM weight_training_result WHERE wtrs_date BETWEEN ? AND ?
		  GROUP BY wtrs_date
		) wo ON wo.wtrs_date = d.date
		GROUP BY YEARWEEK(d.date, 1)
		ORDER BY MIN(d.date)`,
		start, end, start, end, start, end, start, end, start, end, start, end,
	).Scan(&weeklyData)

	// 8. Popular menus (Top 10) — sort count DESC, ชื่อเท่ากันให้เรียง ก-ฮ ต่อ (deterministic
	//    กันผลลัพธ์สลับลำดับไปมาทุกครั้งที่ export เมื่อ count เท่ากันหลายแถว)
	type MenuEntry struct {
		Name  string `gorm:"column:name" json:"name"`
		Count int    `gorm:"column:count" json:"count"`
	}
	var popularMenus []MenuEntry
	config.DB.Raw(`
		SELECT COALESCE(n.ntt_food_name, dn.dntt_food_name, 'อื่นๆ') AS name,
		       COUNT(*) AS count
		FROM daily_nutrition dn
		LEFT JOIN nutrition n ON n.ntt_id = dn.ntt_id
		WHERE dn.dntt_date BETWEEN ? AND ?
		GROUP BY COALESCE(n.ntt_food_name, dn.dntt_food_name, 'อื่นๆ')
		ORDER BY count DESC, name ASC
		LIMIT 10`, start, end,
	).Scan(&popularMenus)

	if chartData    == nil { chartData    = []DayPoint{} }
	if weeklyData   == nil { weeklyData   = []WeekPoint{} }
	if popularMenus == nil { popularMenus = []MenuEntry{} }

	// 9. สมาชิกใหม่ในช่วงเวลาที่กำหนด
	var newMembersCount struct {
		Count int64 `gorm:"column:count"`
	}
	config.DB.Raw(`
		SELECT COUNT(*) AS count
		FROM member_profile
		WHERE DATE(mb_created_at) BETWEEN ? AND ?
	`, start, end).Scan(&newMembersCount)

	c.JSON(http.StatusOK, gin.H{
		"total_members":          totalMembers,
		"new_members_total":      newMembersCount.Count,
		"total_cal_in":           calIn.Total,
		"total_cal_out":          totalCalOut,
		"total_workouts":         totalWorkouts,
		"weight_percent":         weightPercent,
		"cardio_percent":         cardioPercent,
		"total_duration_minutes": totalDuration.Total,
		"chart_data":             chartData,
		"weekly_data":            weeklyData,
		"popular_menus":          popularMenus,
	})
}

