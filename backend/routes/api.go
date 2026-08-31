package routes

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"food_and_fit_api/controllers"
	"food_and_fit_api/middleware"

	"github.com/gin-gonic/gin"
)

// allowedOrigins อ่านรายชื่อ origin ที่อนุญาตจาก .env (คั่นด้วย comma)
// ระบบนี้เป็น REST API ที่ Flutter mobile app เรียกผ่าน Bearer token เป็นหลัก (ไม่ผ่าน browser)
// ตัวแปรนี้มีไว้รองรับกรณีมีหน้าเว็บ (เช่น admin dashboard) ที่ต้องเรียก API ข้าม origin เท่านั้น
func allowedOrigins() []string {
	raw := os.Getenv("ALLOWED_ORIGINS")
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	return parts
}

func SetupRouter() *gin.Engine {
	r := gin.Default()

	origins := allowedOrigins()

	// ✅ CORS Middleware — สะท้อน origin กลับเฉพาะที่อยู่ใน allowlist เท่านั้น (ไม่เปิดกว้างด้วย "*")
	r.Use(func(c *gin.Context) {
		reqOrigin := c.GetHeader("Origin")
		for _, o := range origins {
			if o != "" && o == reqOrigin {
				c.Header("Access-Control-Allow-Origin", reqOrigin)
				c.Header("Vary", "Origin")
				break
			}
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization")
		c.Header("Access-Control-Expose-Headers", "Content-Length")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	})

	// ✅ Security Headers (CSP, X-Frame-Options, ฯลฯ)
	r.Use(middleware.SecurityHeaders())

	// ✅ Rate Limiting ทั่วทั้ง API ป้องกัน DoS/spam (ต่อ IP)
	r.Use(middleware.RateLimitMiddleware(120, time.Minute))

	// ✅ Static Files (อยู่หลัง CORS)
	// ใช้ runtime.Caller เพื่อหา path แบบ absolute โดยอิงจากตำแหน่งไฟล์นี้
	// (ไม่พึ่ง working directory ตอนรัน server เลย รันจากไหนก็เจอ)
	_, currentFile, _, _ := runtime.Caller(0)
	baseDir := filepath.Dir(filepath.Dir(currentFile)) // ถอยจาก routes/ ออกมาเป็นโฟลเดอร์ Backend/
	println("UPLOADS PATH =", filepath.Join(baseDir, "uploads"))

	r.Static("/uploads", filepath.Join(baseDir, "uploads"))
	r.Static("/images", filepath.Join(baseDir, "images"))

	// ✅ ตั้งค่า Trusted Proxies เพื่อให้ Accept connection จากทุก interface
	r.SetTrustedProxies([]string{"127.0.0.1", "localhost", "10.0.2.2", "0.0.0.0", "::", "*"})

	// ==========================================
	// 🌐 API Group
	// ==========================================
	api := r.Group("/api")
	{

		// ==========================================
		// 🔓 Public Routes (ไม่ต้องใช้ Token)
		// จำกัด rate เข้มกว่าเฉลี่ยเพราะเป็นจุดเสี่ยง brute-force/spam OTP
		// ==========================================
		authLimiter := middleware.RateLimitMiddleware(10, time.Minute)
		api.POST("/register", authLimiter, controllers.Register)
		api.POST("/login", authLimiter, controllers.Login)
		api.POST("/logout", middleware.AuthMiddleware(), controllers.Logout)
		api.POST("/verify-email", authLimiter, controllers.VerifyEmail)
		api.POST("/resend-otp", authLimiter, controllers.ResendOTP)
		api.POST("/password/forgot", authLimiter, controllers.RequestOTP)
		api.POST("/password/reset", authLimiter, controllers.ResetPassword)

		// ==========================================
		// 🔑 Admin Routes
		// ==========================================
		admin := api.Group("/admin")
		{
			admin.POST("/login", authLimiter, controllers.AdminLogin)
			admin.POST("/logout", middleware.AdminAuthMiddleware(), controllers.AdminLogout)
			admin.GET("/analytics/overview", middleware.AdminAuthMiddleware(), controllers.GetAdminAnalyticsOverview)
			admin.GET("/dashboard/summary", middleware.AdminAuthMiddleware(), controllers.GetAdminDashboardSummary)

			adminProtected := admin.Group("/")
			adminProtected.Use(middleware.AdminAuthMiddleware())
			{
				// 📊 Admin Analytics — ภาพรวมทุก user
				//adminProtected.GET("/analytics/overview", controllers.GetAdminOverview)

				// 👤 โปรไฟล์ผู้ดูแล + ข้อมูลระบบ (system_data แถวเดียว, C1+E1 ฝั่ง admin web)
				adminProtected.GET("/profile", controllers.GetAdminProfile)
				adminProtected.PUT("/profile", controllers.UpdateAdminProfile)
				adminProtected.PUT("/profile/password", authLimiter, controllers.ChangeAdminPassword)

				// 👥 จัดการสมาชิก (D1 รายชื่อ + D2 รายละเอียด) — อ่านอย่างเดียว
				adminProtected.GET("/members", controllers.GetAllMembers)
				adminProtected.GET("/members/:id", controllers.GetMemberDetail)

				// 🍎🏋️ endpoint กรอง+pagination ระดับ SQL สำหรับหน้าฐานข้อมูลโภชนาการ/ท่าฝึกเวท —
				// แยกจาก /api/nutrition/foods และ /api/exercises/weights เดิมเพราะแอปมือถือเรียก
				// สองตัวนั้นอยู่จริง (ห้ามแก้ signature/response เดิม ดู CLAUDE.md ข้อ 2)
				adminProtected.GET("/nutrition/foods", controllers.GetAdminNutritionFoods)
				adminProtected.GET("/exercises/weights", controllers.GetAdminWeightExercises)

				// ✅ Bulk action (multi-select) หน้าฐานข้อมูลโภชนาการ — id ทั้งหมดตามตัวกรอง (ปุ่ม
				// "เลือกทั้งหมด"), ลบหลายรายการ (ข้าม FK แทนล้มทั้งชุด), ย้ายหมวดหมู่หลายรายการ (ใช้
				// endpoint เดียวกันทำ Undo ได้ด้วยเพราะรับเป็นคู่ id+ปลายทางรายตัว)
				adminProtected.GET("/nutrition/foods/ids", controllers.GetAdminNutritionFoodIds)
				adminProtected.POST("/nutrition/foods/bulk-delete", controllers.BulkDeleteNutritionFoods)
				adminProtected.PUT("/nutrition/foods/bulk-move-category", controllers.BulkMoveNutritionFoodsCategory)

				// 🛡️ จัดการผู้ดูแลระบบ (multi-admin) — list / create / deactivate (soft-disable)
				adminProtected.GET("/admins", controllers.ListAdmins)
				adminProtected.POST("/admins", controllers.CreateAdmin)
				adminProtected.PUT("/admins/:id/deactivate", controllers.DeactivateAdmin)
			}
		}

		// ==========================================
		// 🏋️ Master Data & Exercises (ไม่ต้องมี Token)
		// หน้าบ้านใช้ GET เพื่อโหลดข้อมูลสำหรับแสดงผล
		// POST/PUT/DELETE สำหรับแอดมินจัดการข้อมูล
		// ==========================================
		exerciseMaster := api.Group("/exercises")
		{
			// กลุ่มกล้ามเนื้อ — GET public, POST/PUT/DELETE ต้องเป็น Admin
			exerciseMaster.GET("/muscle-groups", controllers.GetMuscleGroups)
			exerciseMaster.POST("/muscle-groups", middleware.AdminAuthMiddleware(), controllers.CreateMuscleGroup)
			exerciseMaster.PUT("/muscle-groups/:id", middleware.AdminAuthMiddleware(), controllers.UpdateMuscleGroup)
			exerciseMaster.DELETE("/muscle-groups/:id", middleware.AdminAuthMiddleware(), controllers.DeleteMuscleGroup)

			// ท่าเวทเทรนนิ่ง — GET public, POST/PUT/DELETE ต้องเป็น Admin
			exerciseMaster.GET("/weights", controllers.GetWeightExercises)
			exerciseMaster.POST("/weights", middleware.AdminAuthMiddleware(), controllers.CreateWeightExercise)
			exerciseMaster.PUT("/weights/:id", middleware.AdminAuthMiddleware(), controllers.UpdateWeightExercise)
			exerciseMaster.DELETE("/weights/:id", middleware.AdminAuthMiddleware(), controllers.DeleteWeightExercise)

			// คาร์ดิโอ — GET public, POST/PUT/DELETE ต้องเป็น Admin
			exerciseMaster.GET("/cardio", controllers.GetCardioExercises)
			exerciseMaster.POST("/cardio", middleware.AdminAuthMiddleware(), controllers.CreateCardioExercise)
			exerciseMaster.PUT("/cardio/:id", middleware.AdminAuthMiddleware(), controllers.UpdateCardioExercise)
			exerciseMaster.DELETE("/cardio/:id", middleware.AdminAuthMiddleware(), controllers.DeleteCardioExercise)

			// ประเภทคาร์ดิโอ — GET public, POST/PUT/DELETE ต้องเป็น Admin
			exerciseMaster.GET("/cardio-categories", controllers.GetCardioCategories)
			exerciseMaster.POST("/cardio-categories", middleware.AdminAuthMiddleware(), controllers.CreateCardioCategory)
			exerciseMaster.PUT("/cardio-categories/:id", middleware.AdminAuthMiddleware(), controllers.UpdateCardioCategory)
			exerciseMaster.DELETE("/cardio-categories/:id", middleware.AdminAuthMiddleware(), controllers.DeleteCardioCategory)
			// endpoint ใหม่แยกต่างหาก (ไม่แก้ signature ของ Create/Update เดิมที่แอปมือถือส่ง JSON
			// อยู่) — อัปโหลด/แทนที่รูปหมวดหมู่คาร์ดิโอ (multipart) เพิ่งมีคอลัมน์ cdc_image
			exerciseMaster.PUT("/cardio-categories/:id/image", middleware.AdminAuthMiddleware(), controllers.UpdateCardioCategoryImage)
		}

		// ==========================================
		// 🛡️ Protected Routes (ต้องมี Token — Authorization: Bearer <token>)
		// URL prefix: /api/member/...
		// ==========================================
		protected := api.Group("/member")
		protected.Use(middleware.AuthMiddleware())
		{
			// --- โปรไฟล์ผู้ใช้ ---
			// GET  /profile            → ดึงข้อมูลโปรไฟล์ของตัวเอง
			// PUT  /profile            → แก้ไขโปรไฟล์ (ชื่อ, อีเมล ฯลฯ)
			// POST /update-profile     → อัปเดตโปรไฟล์แบบ partial
			// POST /profile/image      → อัปโหลดรูปโปรไฟล์
			protected.POST("/update-profile", controllers.UpdateProfile)
			protected.GET("/profile", controllers.GetProfile)
			protected.PUT("/profile", controllers.EditProfile)
			protected.POST("/profile/image", controllers.UploadProfileImage)

			// --- บัญชีและรหัสผ่าน ---
			// POST   /password/change     → เปลี่ยนรหัสผ่าน (ต้องใส่รหัสเดิม)
			protected.POST("/password/change", controllers.ChangePassword)

			// --- ข้อมูลร่างกาย ---
			// PUT /body-stats          → บันทึกน้ำหนัก/ส่วนสูง/ไขมัน ล่าสุด
			// GET /stats-history       → ดูประวัติข้อมูลร่างกายทั้งหมด
			protected.PUT("/body-stats", controllers.UpdateBodyStats)
			protected.GET("/stats-history", controllers.GetStatsHistory)

			// --- แผนส่วนตัวของ Member ---
			// POST /custom-plans → เริ่มแผนส่วนตัว (ท่าฝึกเก็บลง workout_schedules โดยตรง, wpt_id = NULL)
			protected.POST("/custom-plans", controllers.CreateMemberPlan)

			// --- แผนระบบ (ใช้ร่วมกับ /api/workouts/) ---
			protected.POST("/workout-plans/details", controllers.AddPlanDetail)
			protected.DELETE("/workout-plans/:id/details", controllers.ClearMemberPlanDetails)

			// --- ผลการฝึกเวทเทรนนิ่ง ---
			// POST   /workout-results        → บันทึกผล 1 set
			// GET    /workout-results?date=  → ดูประวัติ
			// DELETE /workout-results/:id    → ลบ 1 set
			protected.POST("/workout-results", controllers.SaveWorkoutResult)
			protected.GET("/workout-results", controllers.GetUserWorkoutResults)
			protected.DELETE("/workout-results/:id", controllers.DeleteWorkoutResult)

			// --- ผลคาร์ดิโอ ---
			// POST   /cardio-results         → บันทึกคาร์ดิโอที่ทำ
			// GET    /cardio-results?date=   → ดูประวัติ
			// DELETE /cardio-results/:id     → ลบรายการคาร์ดิโอ
			protected.POST("/cardio-results", controllers.SaveCardioResult)
			protected.GET("/cardio-results", controllers.GetUserCardioResults)
			protected.DELETE("/cardio-results/:id", controllers.DeleteCardioResult)

			// --- โภชนาการรายวัน ---
			// POST   /nutrition/daily      → บันทึกอาหารที่กินวันนั้น
			// GET    /nutrition/daily?date=→ ดูรายการอาหารวันนั้น
			// PUT    /nutrition/:id        → แก้ไขรายการอาหาร (จำนวน/มื้ออาหาร)
			// DELETE /nutrition/:id        → ลบรายการอาหาร
			protected.POST("/nutrition/daily", controllers.CreateDailyNutrition)
			protected.GET("/nutrition/daily", controllers.GetDailyNutrition)
			protected.PUT("/nutrition/:id", controllers.UpdateDailyNutrition)
			protected.DELETE("/nutrition/:id", controllers.DeleteDailyNutrition)

			// --- Analytics/รายงาน ---
			// GET /analytics/daily    → สรุปแคลอรี่เข้า-ออกรายวัน
			// GET /analytics/weekly   → สรุปรายสัปดาห์
			// GET /analytics/monthly  → สรุปรายเดือน
			// GET /analytics/progress → รายงานความก้าวหน้าภาพรวม
			protected.GET("/analytics/daily", controllers.GetDailyAnalytics)
			protected.GET("/analytics/daily-meals", controllers.GetDailyMealBreakdown)
			protected.GET("/analytics/weekly", controllers.GetWeeklyAnalytics)
			protected.GET("/analytics/monthly", controllers.GetMonthlyAnalytics)
			protected.GET("/analytics/monthly-comparison", controllers.GetMonthlyComparison)
			protected.GET("/analytics/muscle-coverage", controllers.GetMuscleGroupCoverage)
			protected.GET("/analytics/progress", controllers.GetProgressReport)
		}

		// ==========================================
		// 🍎 Nutrition
		// ==========================================
		nutritionGroup := api.Group("/nutrition")
		{
			// GET public, POST/PUT/DELETE ต้องเป็น Admin
			nutritionGroup.GET("/categories", controllers.GetNutritionCategories)
			nutritionGroup.POST("/categories", middleware.AdminAuthMiddleware(), controllers.CreateNutritionCategory)
			nutritionGroup.PUT("/categories/:id", middleware.AdminAuthMiddleware(), controllers.UpdateNutritionCategory)
			nutritionGroup.DELETE("/categories/:id", middleware.AdminAuthMiddleware(), controllers.DeleteNutritionCategory)
			nutritionGroup.PUT("/categories/:id/image", middleware.AdminAuthMiddleware(), controllers.UpdateNutritionCategoryImage)

			nutritionGroup.GET("/foods", controllers.GetAllNutrition)
			nutritionGroup.GET("/foods/search", controllers.SearchNutrition)
			nutritionGroup.POST("/foods", middleware.AdminAuthMiddleware(), controllers.CreateFood)
			nutritionGroup.PUT("/foods/:id", middleware.AdminAuthMiddleware(), controllers.UpdateFood)
			nutritionGroup.DELETE("/foods/:id", middleware.AdminAuthMiddleware(), controllers.DeleteFood)
		}

		// =========================================================
		// 📋 Workout Master Data (ไม่ต้องมี Token)
		// URL: /api/workouts/...
		// ใช้สำหรับโหลดแผนและท่าฝึกเพื่อให้ผู้ใช้เลือก
		// =========================================================
		workoutMaster := api.Group("/workouts")
		{
			// GET  /templates        → ดึงแผนแม่แบบทั้งหมด (2-6 วัน/สัปดาห์) เพื่อให้ผู้ใช้เลือก
			// GET  /plans            → ดึงรายการแผนทั้งหมด
			// POST /plans            → สร้างแผนใหม่
			// PUT  /plans/:id        → แก้ไขแผน
			// DELETE /plans/:id      → ลบแผน
			workoutMaster.GET("/templates", controllers.GetWorkoutTemplates)
			workoutMaster.GET("/plans", controllers.GetWorkoutPlans)
			workoutMaster.POST("/plans", middleware.AdminAuthMiddleware(), controllers.CreateWorkoutPlan)
			workoutMaster.PUT("/plans/:id", middleware.AdminAuthMiddleware(), controllers.UpdateWorkoutPlan)
			workoutMaster.DELETE("/plans/:id", middleware.AdminAuthMiddleware(), controllers.DeleteWorkoutPlan)

			// GET public, POST/PUT/DELETE ต้องเป็น Admin
			workoutMaster.GET("/details", controllers.GetPlanDetails)
			workoutMaster.POST("/details", middleware.AdminAuthMiddleware(), controllers.AddPlanDetail)
			workoutMaster.PUT("/details/:id", middleware.AdminAuthMiddleware(), controllers.UpdatePlanDetail)
			workoutMaster.DELETE("/details/:id", middleware.AdminAuthMiddleware(), controllers.DeletePlanDetail)
		}

		// =========================================================
		// 🛡️ Member Workout (ต้องมี Token)
		// URL: /api/member/...  (ใช้ protected group ที่มี AuthMiddleware)
		// =========================================================
		memberWorkout := protected.Group("/")
		{
			// GET    /workout-plans              → ดึงรายการแผนทั้งหมด (ใช้ตรวจสอบ/จัดการแผน)
			// GET    /workout-plans/active       → ดึงแผนล่าสุดของ member จากประวัติ workout_schedules
			// GET    /workout-plans/details?plan_id= → ดูท่าฝึกในแผนที่เลือก (Preload ชื่อท่า+รูป)
			// POST   /workout-plans/select       → กดเลือกแผน → copy ท่าลง workout_schedules
			//
			// ⚠️ DELETE /workout-plans/:id และ /workout-plans/details/:id ถูกลบออกจากกลุ่มนี้โดยตั้งใจ:
			// WorkoutPlanTemplate/PlanTemplateDetail คือ master data ที่สมาชิกทุกคนใช้ร่วมกัน
			// การลบต้องทำผ่าน /api/workouts/plans/:id และ /api/workouts/details/:id (AdminAuthMiddleware) เท่านั้น
			memberWorkout.GET("/workout-plans", controllers.GetWorkoutPlans)
			memberWorkout.GET("/workout-plans/active", controllers.GetMemberActivePlan)
			memberWorkout.GET("/workout-plans/details", controllers.GetMemberPlanDetails)
			memberWorkout.POST("/workout-plans/select", controllers.SelectWorkoutPlan)

			// "แผนของฉัน" — แผนส่วนตัวของสมาชิกเอง (member_workout_plans) แก้/ลบเองได้ ต่างจาก
			// workout_plans/* ด้านบนที่เป็น master data ร่วมกันทุกคน
			// GET    /workout-plans/mine              → รวมทุกแผนของ user (ระบบที่เคยเลือก + ส่วนตัว)
			// POST   /workout-plans/mine              → สร้างแผนส่วนตัวใหม่
			// PATCH  /workout-plans/mine/:id          → แก้ชื่อแผนส่วนตัว
			// DELETE /workout-plans/mine/:id          → ลบแผนส่วนตัว
			// DELETE /workout-plans/system/:wpt_id    → ลบสำเนาแผนระบบที่ user copy มา (ไม่แตะต้นฉบับ)
			// POST   /workout-plans/activate          → ตั้งแผนที่ใช้งานอยู่ (กันแผนชนกัน)
			memberWorkout.GET("/workout-plans/mine", controllers.GetMyWorkoutPlans)
			memberWorkout.POST("/workout-plans/mine", controllers.CreatePersonalPlan)
			memberWorkout.PATCH("/workout-plans/mine/:id", controllers.RenamePersonalPlan)
			memberWorkout.DELETE("/workout-plans/mine/:id", controllers.DeletePersonalPlan)
			memberWorkout.DELETE("/workout-plans/system/:wpt_id", controllers.DeleteSystemPlanCopy)
			memberWorkout.POST("/workout-plans/activate", controllers.ActivatePlan)
			// POST /workout-plans/fork {wpt_id} → คัดลอกแผนระบบเป็นแผนส่วนตัวใหม่ (mwp_id) แก้ไขได้อิสระ ไม่แตะสำเนา wpt_id เดิม
			memberWorkout.POST("/workout-plans/fork", controllers.ForkWorkoutPlan)

			// GET    /exercises/:wet_id/best-1rm              → ดึง 1RM สูงสุดของ user ในท่านั้น
			memberWorkout.GET("/exercises/:wet_id/best-1rm", controllers.GetBest1RM)
			// GET    /exercises/:wet_id/1rm-history?days=30  → ประวัติ 1RM รายวัน
			memberWorkout.GET("/exercises/:wet_id/1rm-history", controllers.Get1RMHistory)

			// GET    /workout-schedules?plan_id=X&day_number=Y → ดึงท่าออกกำลังกายจากแผนของ user
			// POST   /workout-schedules                       → เพิ่มท่าออกกำลังกายเข้าแผน
			// PATCH  /workout-schedules/:id                    → แก้ sets/reps ของท่าที่มีอยู่แล้ว
			// DELETE /workout-schedules/:id                   → ลบท่าออกจากแผน
			// POST   /workout-plans/reset                     → รีเซ็ตแผน (ระบบ=copy ใหม่, custom=ล้างว่าง)
			memberWorkout.GET("/workout-schedules", controllers.GetUserSchedules)
			memberWorkout.POST("/workout-schedules", controllers.CreateWorkoutSchedule)
			memberWorkout.PATCH("/workout-schedules/:id", controllers.UpdateWorkoutSchedule)
			memberWorkout.DELETE("/workout-schedules/:id", controllers.DeleteWorkoutSchedule)
			memberWorkout.POST("/workout-plans/reset", controllers.ResetWorkoutPlan)

		}

		// ==========================================
		// 🔗 Exercise ↔ Muscle Mapping (ไม่ต้องมี Token)
		// URL: /api/exercise-muscles
		// ใช้แสดงว่าท่าฝึกแต่ละท่าโดนกล้ามเนื้อกลุ่มไหนบ้าง (หลัก/รอง)
		// ==========================================
		mappingGroup := api.Group("/exercise-muscles")
		{
			// GET    /exercise-muscles        → ดึง mapping ท่าฝึก ↔ กล้ามเนื้อทั้งหมด
			// POST   /exercise-muscles        → เพิ่ม mapping ใหม่
			// PUT    /exercise-muscles/:id    → แก้ไข mapping
			// DELETE /exercise-muscles/:id    → ลบ mapping
			mappingGroup.GET("", controllers.GetExerciseMuscleDetails)
			mappingGroup.POST("", middleware.AdminAuthMiddleware(), controllers.CreateExerciseMuscleDetail)
			mappingGroup.PUT("/:id", middleware.AdminAuthMiddleware(), controllers.UpdateExerciseMuscleDetail)
			mappingGroup.DELETE("/:id", middleware.AdminAuthMiddleware(), controllers.DeleteExerciseMuscleDetail)
		}
	}

	return r
}
