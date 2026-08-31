package controllers

import (
	"food_and_fit_api/config"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// GetAdminOverview - ภาพรวมทุก user ในระบบ
// GET /api/admin/analytics/overview?start=2024-01-01&end=2024-01-31
func GetAdminOverview(c *gin.Context) {
	startStr := c.Query("start")
	endStr   := c.Query("end")

	now   := time.Now()
	start := now.AddDate(0, 0, -30)
	end   := now

	if startStr != "" {
		if t, err := time.Parse("2006-01-02", startStr); err == nil {
			start = t
		}
	}
	if endStr != "" {
		if t, err := time.Parse("2006-01-02", endStr); err == nil {
			end = t.Add(24*time.Hour - time.Second)
		}
	}

	// ── 1. จำนวน active members ─────────────────────────────────────────
	var totalMembers int64
	config.DB.Raw(`
		SELECT COUNT(DISTINCT mb_id) FROM (
			SELECT mb_id FROM daily_nutrition        WHERE dntt_date  BETWEEN ? AND ?
			UNION
			SELECT mb_id FROM weight_training_result WHERE wtrs_date  BETWEEN ? AND ?
			UNION
			SELECT mb_id FROM cardio_result          WHERE cdors_date BETWEEN ? AND ?
		) active
	`, start, end, start, end, start, end).Scan(&totalMembers)

	// ── 2. แคลอรีรวมที่กิน ──────────────────────────────────────────────
	// daily_nutrition.dntt_total_calories
	var totalCalIn float64
	config.DB.Raw(`
		SELECT COALESCE(SUM(dntt_total_calories), 0)
		FROM daily_nutrition
		WHERE dntt_date BETWEEN ? AND ?
	`, start, end).Scan(&totalCalIn)

	// ── 3. แคลอรีเผาผลาญรวม ─────────────────────────────────────────────
	// cardio_result.cdors_calories
	var totalCalOut float64
	config.DB.Raw(`
		SELECT COALESCE(SUM(cdors_calories), 0)
		FROM cardio_result
		WHERE cdors_date BETWEEN ? AND ?
	`, start, end).Scan(&totalCalOut)

	// ── 4. จำนวนครั้งออกกำลังกายรวม ─────────────────────────────────────
	var totalWorkouts int64
	config.DB.Raw(`
		SELECT COUNT(*) FROM (
			SELECT wtrs_id AS id FROM weight_training_result WHERE wtrs_date  BETWEEN ? AND ?
			UNION ALL
			SELECT cdors_id AS id FROM cardio_result           WHERE cdors_date BETWEEN ? AND ?
		) all_workouts
	`, start, end, start, end).Scan(&totalWorkouts)

	// ── 5. เวลาออกกำลังกายรวม (นาที) — นับจากคาร์ดิโอเท่านั้น (cdors_duration เก็บเป็นนาทีจริง)
	// เดิมใช้ COUNT(*) จาก workout_schedules ซึ่งเป็นแค่จำนวนแถว template ที่ถูกสร้าง/copy
	// (wsch_date = วันที่สร้างแถว ไม่ใช่วันฝึก, workout_schedules ไม่มี column เวลาเลย) —
	// ตัวเลขที่ได้ไม่ใช่นาทีจริง ไม่สัมพันธ์กับเวลาออกกำลังกายเลย เปลี่ยนมาใช้แหล่งเดียวกับ
	// analytics_controller.go (รายงานรายบุคคล) ให้ตรงกันทั้งระบบ — เวทเทรนนิ่งไม่รวม เพราะ
	// wtrs_duration เป็นวินาทีออกแรงต่อเซต ไม่ใช่ความยาว session รวมตรงๆ ไม่ได้ความหมาย
	var totalDuration int64
	config.DB.Raw(`
		SELECT COALESCE(SUM(cdors_duration), 0)
		FROM cardio_result
		WHERE cdors_date BETWEEN ? AND ?
	`, start, end).Scan(&totalDuration)

	// ── 6. สัดส่วน เวท vs คาร์ดิโอ ──────────────────────────────────────
	var weightCount, cardioCount float64
	config.DB.Raw(`SELECT COUNT(*) FROM weight_training_result WHERE wtrs_date  BETWEEN ? AND ?`, start, end).Scan(&weightCount)
	config.DB.Raw(`SELECT COUNT(*) FROM cardio_result           WHERE cdors_date BETWEEN ? AND ?`, start, end).Scan(&cardioCount)
	totalW := weightCount + cardioCount
	weightPct, cardioPct := 0.0, 0.0
	if totalW > 0 {
		weightPct = weightCount / totalW * 100
		cardioPct = cardioCount / totalW * 100
	}

	// ── 7. weekly_data — กิน vs เผาผลาญ รายสัปดาห์ ──────────────────────
	type WeekPoint struct {
		Label  string  `json:"label"   gorm:"column:label"`
		CalIn  float64 `json:"cal_in"  gorm:"column:cal_in"`
		CalOut float64 `json:"cal_out" gorm:"column:cal_out"`
	}
	var weeklyData []WeekPoint
	// สัปดาห์ที่มีแต่คาร์ดิโอ (ไม่มีบันทึกอาหารเลย) เดิมหายไปทั้งแถว เพราะ LEFT JOIN ขับด้วย
	// daily_nutrition (d) ฝั่งเดียว — สัปดาห์ที่ไม่มีแถวใน d จึงไม่มีอะไรให้ o join เข้ามาได้เลย
	// แก้โดยรวม week_start จากทั้ง 2 ตารางก่อน (UNION) แล้วค่อย LEFT JOIN ทั้ง d และ o เข้ากับ
	// ชุด week_start ที่รวมแล้วนี้ — สัปดาห์ไหนมีแค่ฝั่งเดียวยังโผล่ในผลลัพธ์ อีกฝั่งเป็น 0 ถูกต้อง
	config.DB.Raw(`
		SELECT
			CONCAT('สัปดาห์ที่ ',
				FLOOR(DATEDIFF(weeks.week_start, ?) / 7) + 1
			) AS label,
			COALESCE(d.cal_in,  0) AS cal_in,
			COALESCE(o.cal_out, 0) AS cal_out
		FROM (
			SELECT DATE_SUB(DATE(dntt_date), INTERVAL WEEKDAY(dntt_date) DAY) AS week_start
			FROM daily_nutrition
			WHERE dntt_date BETWEEN ? AND ?
			UNION
			SELECT DATE_SUB(DATE(cdors_date), INTERVAL WEEKDAY(cdors_date) DAY) AS week_start
			FROM cardio_result
			WHERE cdors_date BETWEEN ? AND ?
		) weeks
		LEFT JOIN (
			SELECT
				DATE_SUB(DATE(dntt_date), INTERVAL WEEKDAY(dntt_date) DAY) AS week_start,
				SUM(dntt_total_calories) AS cal_in
			FROM daily_nutrition
			WHERE dntt_date BETWEEN ? AND ?
			GROUP BY week_start
		) d ON weeks.week_start = d.week_start
		LEFT JOIN (
			SELECT
				DATE_SUB(DATE(cdors_date), INTERVAL WEEKDAY(cdors_date) DAY) AS week_start,
				SUM(cdors_calories) AS cal_out
			FROM cardio_result
			WHERE cdors_date BETWEEN ? AND ?
			GROUP BY week_start
		) o ON weeks.week_start = o.week_start
		ORDER BY weeks.week_start ASC
	`, start, start, end, start, end, start, end, start, end).Scan(&weeklyData)

	// ── 8. popular_menus ─────────────────────────────────────────────────
	// nutrition.ntt_food_name  (column จริงจาก DB)
	// daily_nutrition.ntt_id   JOIN  nutrition.ntt_id
	type MenuEntry struct {
		Name  string `json:"name"  gorm:"column:name"`
		Count int    `json:"count" gorm:"column:count"`
	}
	var popularMenus []MenuEntry
	config.DB.Raw(`
		SELECT
			n.ntt_food_name    AS name,
			COUNT(dn.dntt_id)  AS count
		FROM daily_nutrition dn
		JOIN nutrition n ON dn.ntt_id = n.ntt_id
		WHERE dn.dntt_date BETWEEN ? AND ?
		GROUP BY n.ntt_id, n.ntt_food_name
		ORDER BY count DESC
		LIMIT 10
	`, start, end).Scan(&popularMenus)

	// ── 9. chart_data — กิน vs เผาผลาญ รายวัน ───────────────────────────
	type DailyPoint struct {
		Date        string  `json:"date"         gorm:"column:date"`
		CaloriesIn  float64 `json:"calories_in"  gorm:"column:calories_in"`
		CaloriesOut float64 `json:"calories_out" gorm:"column:calories_out"`
	}
	var chartData []DailyPoint
	// pattern เดียวกับ weekly_data ด้านบน: รวมวันที่จากทั้ง 2 ตารางก่อนด้วย UNION แล้วค่อย
	// LEFT JOIN ทั้งฝั่งกินและฝั่งเผาผลาญเข้ามา กันวันที่มีแต่คาร์ดิโอ (ไม่ได้บันทึกอาหาร) หายไป
	config.DB.Raw(`
		SELECT
			days.date,
			COALESCE(d.calories_in,  0) AS calories_in,
			COALESCE(o.calories_out, 0) AS calories_out
		FROM (
			SELECT DATE(dntt_date) AS date FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?
			UNION
			SELECT DATE(cdors_date) AS date FROM cardio_result WHERE cdors_date BETWEEN ? AND ?
		) days
		LEFT JOIN (
			SELECT DATE(dntt_date) AS date,
				SUM(dntt_total_calories) AS calories_in
			FROM daily_nutrition
			WHERE dntt_date BETWEEN ? AND ?
			GROUP BY DATE(dntt_date)
		) d ON days.date = d.date
		LEFT JOIN (
			SELECT DATE(cdors_date) AS date,
				SUM(cdors_calories)  AS calories_out
			FROM cardio_result
			WHERE cdors_date BETWEEN ? AND ?
			GROUP BY DATE(cdors_date)
		) o ON days.date = o.date
		ORDER BY days.date ASC
	`, start, end, start, end, start, end, start, end).Scan(&chartData)

	// ── Response ─────────────────────────────────────────────────────────
	c.JSON(http.StatusOK, gin.H{
		"total_members":          totalMembers,
		"total_cal_in":           totalCalIn,
		"total_cal_out":          totalCalOut,
		"total_workouts":         totalWorkouts,
		"total_duration_minutes": totalDuration, // นาทีจริงจากคาร์ดิโอ (ไม่รวมเวท ดูเหตุผลที่ query ด้านบน)
		"weight_percent":         weightPct,
		"cardio_percent":         cardioPct,
		"weekly_data":            weeklyData,
		"popular_menus":          popularMenus,
		"chart_data":             chartData,
	})
}

// GetAdminWeeklyOverview - 7 วันย้อนหลัง
func GetAdminWeeklyOverview(c *gin.Context) {
	end   := time.Now()
	start := end.AddDate(0, 0, -7)
	_adminChartData(c, start, end)
}

// GetAdminMonthlyOverview - 30 วันย้อนหลัง
func GetAdminMonthlyOverview(c *gin.Context) {
	end   := time.Now()
	start := end.AddDate(0, 0, -30)
	_adminChartData(c, start, end)
}

func _adminChartData(c *gin.Context, start, end time.Time) {
	type DailyPoint struct {
		Date        string  `json:"date"         gorm:"column:date"`
		CaloriesIn  float64 `json:"calories_in"  gorm:"column:calories_in"`
		CaloriesOut float64 `json:"calories_out" gorm:"column:calories_out"`
	}
	var data []DailyPoint
	// pattern เดียวกับ GetAdminOverview ด้านบน — รวมวันที่จากทั้ง 2 ตารางก่อนด้วย UNION กันวันที่
	// มีแต่คาร์ดิโอ (ไม่ได้บันทึกอาหาร) หายไปจากกราฟ
	config.DB.Raw(`
		SELECT
			days.date,
			COALESCE(d.calories_in,  0) AS calories_in,
			COALESCE(o.calories_out, 0) AS calories_out
		FROM (
			SELECT DATE(dntt_date) AS date FROM daily_nutrition WHERE dntt_date BETWEEN ? AND ?
			UNION
			SELECT DATE(cdors_date) AS date FROM cardio_result WHERE cdors_date BETWEEN ? AND ?
		) days
		LEFT JOIN (
			SELECT DATE(dntt_date) AS date,
				SUM(dntt_total_calories) AS calories_in
			FROM daily_nutrition
			WHERE dntt_date BETWEEN ? AND ?
			GROUP BY DATE(dntt_date)
		) d ON days.date = d.date
		LEFT JOIN (
			SELECT DATE(cdors_date) AS date,
				SUM(cdors_calories)  AS calories_out
			FROM cardio_result
			WHERE cdors_date BETWEEN ? AND ?
			GROUP BY DATE(cdors_date)
		) o ON days.date = o.date
		ORDER BY days.date ASC
	`, start, end, start, end, start, end, start, end).Scan(&data)

	c.JSON(http.StatusOK, gin.H{"data": data})
}