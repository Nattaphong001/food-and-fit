package services

import (
	"food_and_fit_api/config"
	"food_and_fit_api/models"
	"math"
	"strconv"
	"strings"
)

// DailyAnalyticsResult - ผลลัพธ์สรุปพลังงานและโภชนาการรายวัน (GetDailyAnalytics)
type DailyAnalyticsResult struct {
	Date             string               `json:"date"`
	Bmi              float64              `json:"bmi"`
	Bmr              float64              `json:"bmr"`
	Tdee             float64              `json:"tdee"`
	IsBmrEstimated   bool                 `json:"is_bmr_estimated"`
	TargetTdee       float64              `json:"target_tdee"`
	TargetProteinG   float64              `json:"target_protein_g"`
	TargetCarbsG     float64              `json:"target_carbs_g"`
	TargetFatG       float64              `json:"target_fat_g"`
	Weight           float64              `json:"weight"`
	GoalType         int                  `json:"goal_type"`
	TotalCaloriesIn  float64              `json:"total_calories_in"`
	TotalCaloriesOut float64              `json:"total_calories_out"`
	Baseline         float64              `json:"baseline"`
	ExerciseBurn     float64              `json:"exercise_burn"`
	Balance          float64              `json:"balance"`
	Macros           DailyAnalyticsMacros `json:"macros"`
}

type DailyAnalyticsMacros struct {
	TotalProtein float64 `json:"total_protein"`
	TotalCarbs   float64 `json:"total_carbs"`
	TotalFat     float64 `json:"total_fat"`
}

// GetDailyAnalyticsData - สรุปพลังงานและโภชนาการรายวัน
func GetDailyAnalyticsData(userID any, date string) DailyAnalyticsResult {
	// 1. หา BMR/TDEE ที่ใช้งานจริงของ "วันที่กำลังดูรายงาน" (แถวล่าสุดที่บันทึกไว้ ณ วันนั้นหรือ
	//    ก่อนหน้า ไม่ใช่ค่าล่าสุดสุดของระบบ กันรายงานวันเก่าใช้ BMR ของวันนี้ผิดๆ)
	var bmrHistory models.MemberBmrHistory
	config.DB.Where("mb_id = ? AND mbh_record_date <= ?", userID, date).
		Order("mbh_record_date desc, mbh_id desc").Limit(1).Find(&bmrHistory)

	isBmrEstimated := bmrHistory.MbhID == 0
	if isBmrEstimated {
		bmrHistory.MbhBmr = FallbackBmr
		bmrHistory.MbhTdee = FallbackTdee
		bmrHistory.MbhTdeeTarget = FallbackTargetTdee
	}

	// 2. รวมพลังงานและสารอาหารที่กินเข้าไป (Calories In)
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

	// 3. รวมพลังงานจากคาร์ดิโอ
	var cardioOut struct {
		Total float64 `gorm:"column:total"`
	}
	config.DB.Model(&models.CardioResult{}).
		Select("COALESCE(SUM(cdors_calories), 0) as total").
		Where("mb_id = ? AND cdors_date = ?", userID, date).
		Scan(&cardioOut)

	// 4. รวมพลังงานจาก Weight Training
	var weightOut struct {
		Total float64 `gorm:"column:total"`
	}
	config.DB.Model(&models.WeightTrainingResult{}).
		Select("COALESCE(SUM(wtrs_calories), 0) as total").
		Where("mb_id = ? AND wtrs_date = ?", userID, date).
		Scan(&weightOut)

	// 5. ดึงข้อมูลน้ำหนัก/เป้าหมาย — ใช้แถว member_body_stats ที่ bmrHistory ผูกไว้ตรงๆ ให้ตรงกับ
	//    ช่วงเวลาเดียวกับ BMR/TDEE ที่เลือกไว้ข้างบน (ไม่ใช่แถวล่าสุดสุดของระบบซึ่งอาจคนละช่วงเวลา)
	var bodyStat models.MemberBodyStat
	if bmrHistory.MbsID != nil {
		config.DB.Where("mbs_id = ?", *bmrHistory.MbsID).First(&bodyStat)
	}
	if bodyStat.MbsID == 0 {
		config.DB.Where("mb_id = ?", userID).Order("mbs_id desc").First(&bodyStat)
	}

	// 6. Total Daily Energy Output = Baseline (BMR × 1.2) + Exercise Burn (คาร์ดิโอ + เวท)
	baseline := CalculateBaselineExpenditure(bmrHistory.MbhBmr)
	exerciseBurn := cardioOut.Total + weightOut.Total
	totalCalOut := baseline + exerciseBurn

	// 7. Energy Balance = พลังงานที่กินเข้า - พลังงานที่ใช้ไปทั้งหมด
	balance := macros.TotalCal - totalCalOut

	// 8. target_tdee: ใช้ค่าที่คำนวณไว้แล้วตอนตั้ง/แก้โปรไฟล์ (mbh_tdee_target) ตรงๆ ไม่คำนวณซ้ำที่นี่
	targetTdee := bmrHistory.MbhTdeeTarget

	// 9. เป้าหมายโปรตีน/คาร์บ/ไขมัน (กรัม) จาก target_tdee ตามสัดส่วนของเป้าหมายที่สมาชิกเลือกไว้
	targetProteinG, targetCarbsG, targetFatG := CalculateMacroTargets(targetTdee, bodyStat.MbsTarget)

	return DailyAnalyticsResult{
		Date:             date,
		Bmi:              bmrHistory.MbhBmi,
		Bmr:              bmrHistory.MbhBmr,
		Tdee:             bmrHistory.MbhTdee,
		IsBmrEstimated:   isBmrEstimated,
		TargetTdee:       targetTdee,
		TargetProteinG:   targetProteinG,
		TargetCarbsG:     targetCarbsG,
		TargetFatG:       targetFatG,
		Weight:           bodyStat.MbsWeight,
		GoalType:         bodyStat.MbsTarget,
		TotalCaloriesIn:  macros.TotalCal,
		TotalCaloriesOut: totalCalOut,
		Baseline:         baseline,
		ExerciseBurn:     exerciseBurn,
		Balance:          balance,
		Macros: DailyAnalyticsMacros{
			TotalProtein: macros.TotalProtein,
			TotalCarbs:   macros.TotalCarb,
			TotalFat:     macros.TotalFat,
		},
	}
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
	TargetTdee  float64 `json:"target_tdee"` // เป้าหมายพลังงานที่ใช้งานจริงของวันนั้น (ไม่ใช่เป้าหมายปัจจุบัน) ให้กราฟสลับเส้นตรงตอนเปลี่ยนเป้าหมายได้จริง
}

// sqlConstReplacer แทนที่ placeholder {{...}} ในข้อความ SQL ด้วยค่าคงที่จริงจาก calculator.go
// ตอนเริ่มโปรแกรม — กันไม่ให้ตัวเลขสูตร (เช่น ×1.2, ค่าประมาณ BMR ตอนไม่มีประวัติ) ต้องพิมพ์ซ้ำเป็น
// ตัวเลขดิบๆ ใน SQL (ค่ามาจาก constant เท่านั้น ไม่มี input จากผู้ใช้ปนเลย จึงต่อ string ได้ปลอดภัย)
var sqlConstReplacer = strings.NewReplacer(
	"{{SEDENTARY_COEFFICIENT}}", strconv.FormatFloat(SedentaryCoefficient, 'f', -1, 64),
	"{{FALLBACK_BMR}}", strconv.FormatFloat(FallbackBmr, 'f', -1, 64),
	"{{FALLBACK_TARGET_TDEE}}", strconv.FormatFloat(FallbackTargetTdee, 'f', -1, 64),
)

// dailySumBetweenSQL สรุปพลังงานเข้า/ออกรายวันของช่วงวันที่ระบุ (ใช้กับกราฟ weekly/monthly)
// แต่ละวันในผลลัพธ์ใช้ baseline (BMR×1.2) และ target_tdee ของ "วันนั้นๆ" เอง (หาแถว
// member_bmr_history ล่าสุดที่ไม่เกินวันนั้น) ไม่ใช่ค่า BMR ปัจจุบันค่าเดียวลากยาวทั้งกราฟ —
// ถ้าผู้ใช้แก้น้ำหนัก/เป้าหมายกลางช่วงที่ดูรายงาน แต่ละวันจะยังใช้ BMR ที่ถูกต้องของวันนั้น
var dailySumBetweenSQL = sqlConstReplacer.Replace(`
	SELECT date_list.date,
		   COALESCE(SUM(dn.dntt_total_calories), 0) as calories_in,
		   (COALESCE((SELECT mbh.mbh_bmr FROM member_bmr_history mbh
		              WHERE mbh.mb_id = ? AND mbh.mbh_record_date <= date_list.date
		              ORDER BY mbh.mbh_record_date DESC, mbh.mbh_id DESC LIMIT 1), {{FALLBACK_BMR}}) * {{SEDENTARY_COEFFICIENT}})
	     + COALESCE(cr_sum.total_out, 0) + COALESCE(wt_sum.total_out, 0) as calories_out,
		   COALESCE(cr_sum.total_out, 0) as cardio_out,
		   COALESCE(wt_sum.total_out, 0) as weight_out,
		   COALESCE(SUM(dn.dntt_total_protein), 0) as protein,
		   COALESCE(SUM(dn.dntt_total_carb), 0) as carbs,
		   COALESCE(SUM(dn.dntt_total_fat), 0) as fat,
		   COALESCE((SELECT mbh.mbh_tdee_target FROM member_bmr_history mbh
		             WHERE mbh.mb_id = ? AND mbh.mbh_record_date <= date_list.date
		             ORDER BY mbh.mbh_record_date DESC, mbh.mbh_id DESC LIMIT 1), {{FALLBACK_TARGET_TDEE}}) as target_tdee
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
`)

// GetDailySumBetween - สรุปรายวันช่วง startDate..endDate (ใช้ร่วมกันทั้ง weekly/monthly analytics)
func GetDailySumBetween(userID any, startDate, endDate string) []DailySum {
	var results []DailySum
	config.DB.Raw(dailySumBetweenSQL,
		userID, userID, userID, userID, userID, userID, userID, userID, startDate, endDate,
	).Scan(&results)
	return results
}

// ProgressReportResult - รายงานความคืบหน้า (น้ำหนัก, พลังงานเฉลี่ย, จำนวนครั้งที่ซ้อม)
type ProgressReportResult struct {
	WeightChange    float64     `json:"weight_change"`
	CalorieAvg      float64     `json:"calorie_avg"`
	WorkoutCount    int         `json:"workout_count"`
	ProgressPercent float64     `json:"progress_percent"`
	BodyHistory     []BodyPoint `json:"body_history"`
}

type BodyPoint struct {
	Date          string  `json:"date"`
	Weight        float64 `json:"weight"`
	Bmi           float64 `json:"bmi"`
	ActivityLevel float64 `json:"activity_level"`
	Target        int     `json:"target"`
}

// GetProgressReportData - รายงานความคืบหน้า (น้ำหนัก, พลังงานเฉลี่ย, จำนวนครั้งที่ซ้อม)
func GetProgressReportData(userID any, days string) ProgressReportResult {
	// 1. ประวัติน้ำหนักและ BMI — 1 วัน แสดงแค่ 1 จุด (เอาแถวล่าสุดของวันนั้นถ้าแก้หลายครั้งในวัน
	//    เดียวกัน) พร้อมแนบ activity_level/target ต่อจุด ให้ frontend mark วันที่เปลี่ยนระดับ
	//    กิจกรรม/เป้าหมายบนกราฟได้
	var bodyHistory []BodyPoint
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

	// 2. พลังงานที่กินเข้าไปเฉลี่ยต่อวัน
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

	return ProgressReportResult{
		WeightChange:    weightChange,
		CalorieAvg:      avgCal.Avg,
		WorkoutCount:    workoutCount.Count,
		ProgressPercent: progressPercent,
		BodyHistory:     bodyHistory,
	}
}

// MealRow - แถวสรุปพลังงาน/สารอาหารต่อมื้อ (GetDailyMealBreakdown)
type MealRow struct {
	MealType int     `gorm:"column:meal_type" json:"meal_type"`
	Calories float64 `gorm:"column:calories"  json:"calories"`
	Protein  float64 `gorm:"column:protein"   json:"protein"`
	Carbs    float64 `gorm:"column:carbs"     json:"carbs"`
	Fat      float64 `gorm:"column:fat"       json:"fat"`
	Count    int     `gorm:"column:count"     json:"count"`
}

// GetDailyMealBreakdownData - แบ่งอาหารตามมื้อ (1=เช้า 2=กลางวัน 3=เย็น 4=ว่าง)
func GetDailyMealBreakdownData(userID any, date string) []MealRow {
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
	return rows
}

// RMPoint - จุดประวัติ 1RM รายวัน (Get1RMHistory)
type RMPoint struct {
	Date       string  `gorm:"column:date"       json:"date"`
	Best1RM    float64 `gorm:"column:best_1rm"   json:"best_1rm"`
	BestWeight float64 `gorm:"column:best_weight" json:"best_weight"`
	BestReps   int     `gorm:"column:best_reps"  json:"best_reps"`
}

// Get1RMHistoryData - ประวัติ 1RM รายวัน สำหรับท่าฝึกที่ระบุ
func Get1RMHistoryData(userID any, wetID string, days string) []RMPoint {
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
	return rows
}

// MonthStat - สถิติสรุปต่อเดือน (GetMonthlyComparison)
type MonthStat struct {
	AvgCal       float64 `gorm:"column:avg_cal"`
	WorkoutDays  int     `gorm:"column:workout_days"`
	AvgCardio    float64 `gorm:"column:avg_cardio"`
	AvgWeight    float64 `gorm:"column:avg_weight"`
	RecordedDays int     `gorm:"column:recorded_days"` // จำนวนวันที่มีบันทึกอาหารจริงในช่วง (avg_cal หารด้วยตัวนี้ ไม่ใช่จำนวนวันปฏิทิน)
}

type MonthlyComparisonResult struct {
	ThisMonth     MonthStat
	LastMonth     MonthStat
	CalChangePct  float64
	WorkoutChange int
}

// GetMonthlyComparisonData - เปรียบเทียบเดือนนี้ vs เดือนที่แล้ว
// refDate = "" ใช้ CURDATE() (เดือนปัจจุบันจริง), ไม่ว่าง = ใช้วันที่นี้เป็นฐาน (รูปแบบ YYYY-MM-DD)
func GetMonthlyComparisonData(userID any, refDate string) MonthlyComparisonResult {
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
	// เดือนที่จะเทียบ — มาจากพารามิเตอร์ refDate (เดือนที่ frontend กำลังเลื่อนดูอยู่)
	// ไม่ส่งมา = ใช้เดือนปัจจุบันจริง
	refDateExpr := "CURDATE()"
	if refDate != "" {
		refDateExpr = "'" + refDate + "'"
	}
	thisMonth := queryMonthStat("DATE_FORMAT("+refDateExpr+",'%Y-%m-01')", "LAST_DAY("+refDateExpr+")")
	lastMonth := queryMonthStat("DATE_FORMAT(DATE_SUB("+refDateExpr+",INTERVAL 1 MONTH),'%Y-%m-01')",
		"LAST_DAY(DATE_SUB("+refDateExpr+",INTERVAL 1 MONTH))")

	calChangePct := 0.0
	if lastMonth.AvgCal > 0 {
		calChangePct = (thisMonth.AvgCal - lastMonth.AvgCal) / lastMonth.AvgCal * 100
	}
	return MonthlyComparisonResult{
		ThisMonth:     thisMonth,
		LastMonth:     lastMonth,
		CalChangePct:  calChangePct,
		WorkoutChange: thisMonth.WorkoutDays - lastMonth.WorkoutDays,
	}
}

// CoverageRow - กล้ามเนื้อที่ฝึกในช่วง N วัน (GetMuscleGroupCoverage)
type CoverageRow struct {
	MugID       uint   `gorm:"column:mug_id"       json:"mug_id"`
	MugName     string `gorm:"column:mug_name"     json:"mug_name"`
	MugZone     int8   `gorm:"column:mug_zone"     json:"mug_zone"`
	TrainedDays int    `gorm:"column:trained_days" json:"trained_days"`
	LastTrained string `gorm:"column:last_trained" json:"last_trained"`
}

// GetMuscleGroupCoverageData - กล้ามเนื้อที่ฝึกในช่วง N วัน
func GetMuscleGroupCoverageData(userID any, days string) []CoverageRow {
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
	return rows
}

// AdminAnalyticsOverview - สรุปข้อมูลภาพรวมสำหรับแอดมิน (GetAdminAnalyticsOverview)
type AdminAnalyticsOverview struct {
	TotalMembers         int64
	NewMembersTotal      int64
	TotalCalIn           float64
	TotalCalOut          float64
	TotalWorkouts        int64
	WeightPercent        float64
	CardioPercent        float64
	TotalDurationMinutes int64
	ChartData            []DayPoint
	WeeklyData           []WeekPoint
	PopularMenus         []MenuEntry
}

type DayPoint struct {
	Date        string  `gorm:"column:date" json:"date"`
	CaloriesIn  float64 `gorm:"column:calories_in" json:"calories_in"`
	CaloriesOut float64 `gorm:"column:calories_out" json:"calories_out"`
}

type WeekPoint struct {
	Label  string  `gorm:"column:label" json:"label"`
	CalIn  float64 `gorm:"column:cal_in" json:"cal_in"`
	CalOut float64 `gorm:"column:cal_out" json:"cal_out"`
}

type MenuEntry struct {
	Name  string `gorm:"column:name" json:"name"`
	Count int    `gorm:"column:count" json:"count"`
}

// GetAdminAnalyticsOverviewData - สรุปข้อมูลภาพรวมสำหรับแอดมิน ช่วง start..end (YYYY-MM-DD)
func GetAdminAnalyticsOverviewData(start, end string) AdminAnalyticsOverview {
	// 1. จำนวนสมาชิกทั้งหมด
	var totalMembers int64
	config.DB.Raw("SELECT COUNT(*) FROM member_profile").Scan(&totalMembers)

	// 2. พลังงานเข้า (รวมทุกคน ในช่วง start–end)
	var calIn struct{ Total float64 }
	config.DB.Raw(`SELECT COALESCE(SUM(dntt_total_calories), 0) as total
		FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?`, start, end).Scan(&calIn)

	// 3. พลังงานออก = Baseline (BMR×1.2 ต่อวันที่มีกิจกรรม ของแต่ละสมาชิก) + คาร์ดิโอ + เวท
	//    (นิยามเดียวกับ Total Daily Energy Output ของ GetDailyAnalyticsData ข้อ 6 ด้านบน)
	var cardioCalOut struct{ Total float64 }
	config.DB.Raw(`SELECT COALESCE(SUM(cdors_calories), 0) as total
		FROM cardio_result WHERE cdors_date BETWEEN ? AND ?`, start, end).Scan(&cardioCalOut)

	var weightCalOut struct{ Total float64 }
	config.DB.Raw(`SELECT COALESCE(SUM(wtrs_calories), 0) as total
		FROM weight_training_result WHERE wtrs_date BETWEEN ? AND ?`, start, end).Scan(&weightCalOut)

	// Baseline รวมทุกคน = ผลรวมของ (Baseline ต่อวันของสมาชิกแต่ละคน × จำนวนวันที่คนนั้นมีกิจกรรมในช่วง)
	// สมาชิกที่ไม่เคยมีประวัติ BMR เลย ใช้ FallbackBmr แทน (ค่าเดียวกับที่ GetDailyAnalyticsData ใช้)
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
		                 ORDER BY mbh2.mbh_id DESC LIMIT 1), ?) AS bmr
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
	`, FallbackBmr, start, end, start, end, start, end).Scan(&baselineRows)

	var baselineTotal float64
	for _, row := range baselineRows {
		baselineTotal += CalculateBaselineExpenditure(row.Bmr) * float64(row.Days)
	}

	totalCalOut := baselineTotal + cardioCalOut.Total + weightCalOut.Total

	// 4. จำนวน session การฝึก
	var weightSessions struct{ Count int64 }
	config.DB.Raw(`SELECT COUNT(*) as count FROM (
		SELECT DISTINCT mb_id, wtrs_date FROM weight_training_result
		WHERE wtrs_date BETWEEN ? AND ?) t`, start, end).Scan(&weightSessions)

	// นับแบบ DISTINCT mb_id+date เหมือน weightSessions ด้านบน (นับเป็น "1 ครั้ง" ต่อคนต่อวัน
	// เหมือนกัน ไม่ว่าจะบันทึกกี่รอบในวันนั้น) ให้หน่วยนับตรงกันทั้งเวทและคาร์ดิโอ
	var cardioSessions struct{ Count int64 }
	config.DB.Raw(`SELECT COUNT(*) as count FROM (
		SELECT DISTINCT mb_id, cdors_date FROM cardio_result
		WHERE cdors_date BETWEEN ? AND ?) t`, start, end).Scan(&cardioSessions)

	totalWorkouts := weightSessions.Count + cardioSessions.Count
	// สัดส่วน weight/cardio คิดจาก "จำนวนครั้งที่บันทึก" ไม่ใช่พลังงานหรือเวลา (เวทเทรนนิ่งไม่มี
	// ฟิลด์เก็บเวลา จึงใช้จำนวนครั้งเป็นหน่วยเดียวที่เทียบกันได้ทั้งสองกิจกรรม)
	weightPercent, cardioPercent := 0.0, 0.0
	if totalWorkouts > 0 {
		weightPercent = float64(weightSessions.Count) / float64(totalWorkouts) * 100
		cardioPercent = float64(cardioSessions.Count) / float64(totalWorkouts) * 100
	}

	// 5. เวลาออกกำลังกายรวม (นาที) จากคาร์ดิโอ — cdors_duration เก็บเป็นวินาทีในฐานข้อมูล
	// ต้องหาร 60 ก่อนแปลงเป็นนาที
	var totalDuration struct{ Total int64 }
	config.DB.Raw(`SELECT COALESCE(SUM(cdors_duration), 0) as total
		FROM cardio_result WHERE cdors_date BETWEEN ? AND ?`, start, end).Scan(&totalDuration)
	totalDurationMinutes := int64(math.Round(float64(totalDuration.Total) / 60.0))

	// 6. Chart data (รายวัน) — calories_out รวมทั้งคาร์ดิโอและเวทเทรนนิ่ง (Exercise Burn เต็มนิยาม)
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

	// 7. Weekly data — cal_out รวมคาร์ดิโอ+เวทเหมือน chart_data ด้านบน จัดกลุ่มเป็นรายสัปดาห์
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

	// 8. เมนูยอดนิยม 10 อันดับแรก — เรียงจำนวนครั้งมากไปน้อย ชื่อเท่ากันเรียง ก-ฮ ต่อ (กันลำดับสลับ
	//    ไปมาเวลา count เท่ากันหลายแถว)
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

	if chartData == nil {
		chartData = []DayPoint{}
	}
	if weeklyData == nil {
		weeklyData = []WeekPoint{}
	}
	if popularMenus == nil {
		popularMenus = []MenuEntry{}
	}

	// 9. สมาชิกใหม่ในช่วงเวลาที่กำหนด
	var newMembersCount struct {
		Count int64 `gorm:"column:count"`
	}
	config.DB.Raw(`
		SELECT COUNT(*) AS count
		FROM member_profile
		WHERE DATE(mb_created_at) BETWEEN ? AND ?
	`, start, end).Scan(&newMembersCount)

	return AdminAnalyticsOverview{
		TotalMembers:         totalMembers,
		NewMembersTotal:      newMembersCount.Count,
		TotalCalIn:           calIn.Total,
		TotalCalOut:          totalCalOut,
		TotalWorkouts:        totalWorkouts,
		WeightPercent:        weightPercent,
		CardioPercent:        cardioPercent,
		TotalDurationMinutes: totalDurationMinutes,
		ChartData:            chartData,
		WeeklyData:           weeklyData,
		PopularMenus:         popularMenus,
	}
}
