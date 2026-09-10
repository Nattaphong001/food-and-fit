package models

import "time"

// 1. ตารางข้อมูลกลุ่มกล้ามเนื้อ (Muscle Group)
type MuscleGroup struct {
	MugID    uint   `gorm:"primaryKey;column:mug_id;autoIncrement" json:"mug_id"`
	MugName  string `gorm:"type:varchar(100);column:mug_name" json:"mug_name"`
	MugZone  int8   `gorm:"type:tinyint;column:mug_zone" json:"mug_zone"` // 1=บน, 2=ล่าง, 3=แกนกลาง
	MugImage string `gorm:"type:varchar(255);column:mug_image" json:"mug_image"`
}

func (MuscleGroup) TableName() string {
	return "muscle_group"
}

// 2. ตารางข้อมูลท่าฝึกเวทเทรนนิ่ง (Weight Exercises)
// mug_id/MuscleGroup ถูกลบออกจาก struct นี้แล้ว (2026-09-04) — คอลัมน์ weight_exercises.mug_id
// ถูก DROP ออกจาก DB จริงไปตั้งแต่ migration รอบ 1 STEP 7 เก็บกล้ามเนื้อหลักได้แค่มัดเดียว/ท่า
// ข้อมูลจริงมี 71% ของท่าที่มีกล้ามเนื้อหลักมากกว่า 1 มัด ต้องอ่านผ่าน MuscleDetails
// (exercise_muscle_details, exm_type 1=หลัก/2=รอง) แทนเสมอ — ดู admin_exercise_controller.go
// บรรทัด ~29-34 ที่อธิบายเหตุผลเดียวกันนี้ไว้แล้วฝั่ง filter
type WeightExercise struct {
	WetID           uint                   `gorm:"primaryKey;column:wet_id;autoIncrement" json:"wet_id"`
	WetName         string                 `gorm:"type:varchar(100);column:wet_name" json:"wet_name"`
	WetDescription  string                 `gorm:"type:text;column:wet_description" json:"wet_description"`
	WetTechnique    string                 `gorm:"type:text;column:wet_technique" json:"wet_technique"`
	WetImage        string                 `gorm:"type:varchar(255);column:wet_image" json:"wet_image"`
	WetVideo        string                 `gorm:"type:varchar(255);column:wet_video" json:"wet_video"`
	WetLoopVideo    string                 `gorm:"type:varchar(255);column:wet_loop_video" json:"wet_loop_video"`
	WetDifficulty   int8                   `gorm:"type:tinyint;column:wet_difficulty" json:"wet_difficulty"`
	WetEquipment    int8                   `gorm:"type:tinyint;column:wet_equipment" json:"wet_equipment"`
	WetExerciseType int8                   `gorm:"type:tinyint;column:wet_exercise_type" json:"wet_exercise_type"` // 1=หลายกลุ่ม 2=เฉพาะส่วน
	// MET พื้นฐานของท่านี้ ใช้เป็นจุดตั้งต้นของ Smart Auto Calorie (เพิ่มเข้ามา 2026-09-08) — ดู
	// services.CalculateWeightTrainingCalories และ migrations/2026-09-08_add_weight_calorie_calc_columns.sql
	WetBaseMet      float64                `gorm:"type:decimal(3,1);column:wet_base_met;not null" json:"wet_base_met"`
	MuscleDetails   []ExerciseMuscleDetail `gorm:"foreignKey:WetID;references:WetID" json:"muscle_details"`
}

func (WeightExercise) TableName() string {
	return "weight_exercises"
}

// 3. ตารางรายละเอียดกลุ่มกล้ามเนื้อในท่าฝึก (Exercise Muscle Details)
type ExerciseMuscleDetail struct {
	EmdID       uint        `gorm:"primaryKey;column:emd_id;autoIncrement" json:"emd_id"`
	ExmType     int8        `gorm:"type:tinyint;column:exm_type" json:"exm_type"` // 1=หลัก, 2=รอง
	WetID       uint        `gorm:"column:wet_id" json:"wet_id"`
	MugID       uint        `gorm:"column:mug_id" json:"mug_id"`
	MuscleGroup MuscleGroup `gorm:"foreignKey:MugID;references:MugID" json:"muscle_group"`
}

func (ExerciseMuscleDetail) TableName() string {
	return "exercise_muscle_details"
}

// 4. ตารางข้อมูลประเภทคาร์ดิโอ (Cardio Category)
type CardioCategory struct {
	CdcID          uint   `gorm:"primaryKey;column:cdc_id;autoIncrement" json:"cdc_id"`
	CdcName        string `gorm:"type:varchar(100);column:cdc_name" json:"cdc_name"`
	CdcDescription string `gorm:"type:text;column:cdc_description" json:"cdc_description"`
	CdcImage       string `gorm:"type:varchar(255);column:cdc_image" json:"cdc_image"`
}

func (CardioCategory) TableName() string {
	return "cardio_category"
}

// 5. ตารางข้อมูลกิจกรรมคาร์ดิโอ (Cardio)
type Cardio struct {
	CdoID          uint    `gorm:"primaryKey;column:cdo_id;autoIncrement" json:"cdo_id"`
	CdoName        string  `gorm:"type:varchar(100);column:cdo_name" json:"cdo_name"`
	CdoMets        float64 `gorm:"type:decimal(4,2);column:cdo_mets" json:"cdo_mets"`
	CdoDescription string  `gorm:"type:text;column:cdo_description" json:"cdo_description"`
	CdoTechnique   string  `gorm:"type:text;column:cdo_technique" json:"cdo_technique"`
	CdoImage       string  `gorm:"type:varchar(255);column:cdo_image" json:"cdo_image"`
	CdoVideo       string  `gorm:"type:varchar(255);column:cdo_video" json:"cdo_video"`
	CdoLoopVideo   string  `gorm:"type:varchar(255);column:cdo_loop_video" json:"cdo_loop_video"`
	CdcID          uint    `gorm:"column:cdc_id" json:"cdc_id"`
	CdoHasDistance int8    `gorm:"type:tinyint;column:cdo_has_distance;default:0" json:"cdo_has_distance"`
}

func (Cardio) TableName() string {
	return "cardio"
}

// 6. ตารางแผนการฝึก (Workout Plan Template)
//    ⚠️  DB ใช้ wpt_ prefix — ห้ามเปลี่ยนชื่อ column โดยไม่ migrate DB
type WorkoutPlanTemplate struct {
	WptID          uint   `gorm:"primaryKey;column:wpt_id;autoIncrement" json:"wpt_id"`
	WptName        string `gorm:"type:varchar(100);column:wpt_name" json:"wpt_name"`
	WptDaysPerWeek int    `gorm:"type:int;column:wpt_days_per_week" json:"wpt_days_per_week"`
	WptDifficulty  int8   `gorm:"type:tinyint;column:wpt_difficulty" json:"wpt_difficulty"` // 1=Beginner, 2=Intermediate, 3=Advanced
	WptDescription string `gorm:"type:text;column:wpt_description" json:"wpt_description"`
	WptImage       string `gorm:"type:varchar(255);column:wpt_image" json:"wpt_image"`
}

func (WorkoutPlanTemplate) TableName() string {
	return "workout_plan_template"
}

// 7. ตารางรายละเอียดแผน (Plan Template Detail) — เก็บเฉพาะท่าเวทเทรนนิ่งในแผนแม่แบบ
//    เดิมออกแบบให้ผูกได้ทั้งเวทและคาร์ดิโอ (มีคอลัมน์ cdo_id) แต่ภายหลังแยกคาร์ดิโอออกจากแผนฝึก
//    เหลือเฉพาะเวท คอลัมน์ cdo_id จึงถูกลบออกจาก DB ไปแล้ว (ไม่มีอยู่ใน schema ปัจจุบัน)
//    ⚠️  DB ใช้ ptd_ prefix และ wpt_id (ไม่ใช่ plan_id)
//    PtdReps เป็น VARCHAR เช่น "8-10", "12-15"
type PlanTemplateDetail struct {
	PtdID          uint           `gorm:"primaryKey;column:ptd_id;autoIncrement" json:"ptd_id"`
	WptID          uint           `gorm:"column:wpt_id" json:"wpt_id"`
	PtdDayNumber   int            `gorm:"type:int;column:ptd_day_number" json:"ptd_day_number"`
	PtdDayName     string         `gorm:"type:varchar(50);column:ptd_day_name" json:"ptd_day_name"`
	WetID          *uint          `gorm:"column:wet_id" json:"wet_id"`
	PtdSets        int            `gorm:"type:int;column:ptd_sets" json:"ptd_sets"`
	PtdReps        string         `gorm:"type:varchar(20);column:ptd_reps" json:"ptd_reps"`
	PtdRestSeconds int            `gorm:"column:ptd_rest_seconds;default:90" json:"ptd_rest_seconds"`
	PtdOrder       int            `gorm:"type:int;column:ptd_order" json:"ptd_order"`
	WeightExercise WeightExercise `gorm:"foreignKey:WetID;references:WetID" json:"weight_exercise"`
}

func (PlanTemplateDetail) TableName() string {
	return "plan_template_detail"
}

// Getters ด้านล่างมีไว้ให้ helpers.ValidatePlanTemplateDetail เรียกผ่าน interface กลาง
// (helpers ห้าม import models ตรงๆ เพราะ models ไม่ import helpers อยู่แล้ว แต่กันไว้ไม่ให้เกิด cycle ในอนาคต)
func (d PlanTemplateDetail) GetPtdDayNumber() int   { return d.PtdDayNumber }
func (d PlanTemplateDetail) GetPtdDayName() string  { return d.PtdDayName }
func (d PlanTemplateDetail) GetPtdSets() int        { return d.PtdSets }
func (d PlanTemplateDetail) GetPtdReps() string     { return d.PtdReps }
func (d PlanTemplateDetail) GetPtdRestSeconds() int { return d.PtdRestSeconds }

// 8. ตารางฝึกเวทเทรนนิ่ง (Workout Schedules) — เก็บแผนของผู้ใช้ 1 คนต่อ 1 แผนเสมอ (mb_id)
// หมายเหตุ: type: tag ระบุชัดเจนกัน GORM AutoMigrate เดา type เป็น bigint แทน int ตาม default ของมัน
//
// ยุบรวม member_workout_plans เข้าตารางนี้แล้ว (2026-09-04, เลิกใช้ตารางแยกเพราะเป็น 1:1 กับ
// สมาชิกอยู่แล้ว ไม่มีเหตุผลต้องมีตาราง header ต่างหาก) ข้อมูลระดับแผน (ชื่อแผน/จำนวนวันต่อสัปดาห์/
// แม่แบบต้นทาง/เวลาสร้าง-แก้ไข) เก็บซ้ำในทุกแถวท่าฝึกของแผนเดียวกัน (denormalize โดยตั้งใจ — ไม่มี
// endpoint ไหนแก้ wsch_days_per_week ทีหลัง ส่วน wsch_plan_name ตอน RenamePersonalPlan ต้อง
// UPDATE ทุกแถวของ mb_id นั้นพร้อมกัน)
//
// แถวที่ WetID == nil (wsch_day_number = 0) คือ "หัวแผน" (plan header) — ใช้เก็บชื่อแผน/จำนวนวัน
// ตอนสมาชิกสร้างแผนส่วนตัวใหม่แต่ยังไม่ได้เพิ่มท่าใดๆ (ไม่งั้นไม่มีที่เก็บชื่อแผนเลยถ้าไม่มีท่าสักท่า)
// ทุก query ที่ต้องการ "ท่าฝึกจริง" เท่านั้น (listing/isSystemPlanModified/นับจำนวนวัน) ต้องกรอง
// wet_id IS NOT NULL หรือ wsch_day_number > 0 เสมอ ไม่งั้นแถวหัวแผนจะปนเข้าไป
//
// mwp_source_wpt_id (เดิม) → เปลี่ยนชื่อเป็น wpt_id ตรงๆ (ตามธรรมเนียม FK column ใช้ชื่อ PK ของ
// ตารางที่อ้างถึง) NULL = แผนสร้างเอง, ไม่ NULL = copy มาจากแม่แบบระบบ — "แผนระบบ" กับ "แผนส่วนตัว"
// จึงไม่แยกกันที่ตารางนี้ (เหมือนดีไซน์ก่อนหน้าผ่าน member_workout_plans)
type WorkoutSchedule struct {
	WschID             uint           `gorm:"primaryKey;column:wsch_id;autoIncrement" json:"wsch_id"`
	WschPlanName       string         `gorm:"type:varchar(100);column:wsch_plan_name" json:"wsch_plan_name"`
	WschDaysPerWeek    int            `gorm:"type:int;column:wsch_days_per_week;default:3" json:"wsch_days_per_week"`
	WschDayNumber      int            `gorm:"type:int;column:wsch_day_number;default:0" json:"wsch_day_number"`
	WschDayName        string         `gorm:"type:varchar(50);column:wsch_day_name" json:"wsch_day_name"`
	WschOrder          int            `gorm:"type:int;column:wsch_order" json:"wsch_order"`
	WschSets           int            `gorm:"type:int;column:wsch_sets;default:3" json:"wsch_sets"`
	WschReps           string         `gorm:"type:varchar(20);column:wsch_reps;default:'10'" json:"wsch_reps"`
	WschRestSeconds    int            `gorm:"type:int;column:wsch_rest_seconds;default:90" json:"wsch_rest_seconds"`
	WschPlanCreatedAt  time.Time      `gorm:"column:wsch_plan_created_at;autoCreateTime" json:"wsch_plan_created_at"`
	WschPlanUpdatedAt  time.Time      `gorm:"column:wsch_plan_updated_at;autoUpdateTime" json:"wsch_plan_updated_at"`
	MbID               uint           `gorm:"type:int(11);column:mb_id" json:"mb_id"`
	WptID              *uint          `gorm:"type:int unsigned;column:wpt_id" json:"wpt_id"`
	WetID              *uint          `gorm:"type:int unsigned;column:wet_id" json:"wet_id"`
	WeightExercise     WeightExercise `gorm:"foreignKey:WetID;references:WetID" json:"weight_exercise"`
}

func (WorkoutSchedule) TableName() string {
	return "workout_schedules"
}

// 10. ตารางผลการฝึกเวท
// หมายเหตุ: ทุก type: tag ด้านล่างระบุไว้ชัดเจนเพื่อกัน GORM AutoMigrate เดา type เป็น bigint
// (ตาราง Datadic กำหนดเป็น INT ทั้งหมด — type: tag ด้านล่างต้องตรงกับ Datadic เสมอ)
type WeightTrainingResult struct {
	WtrsID             uint           `gorm:"primaryKey;column:wtrs_id;autoIncrement" json:"wtrs_id"`
	WtrsDate           string         `gorm:"type:date;column:wtrs_date;not null" json:"wtrs_date"`
	WtrsSetNo          int            `gorm:"type:tinyint unsigned;column:wtrs_set_no" json:"wtrs_set_no"`
	WtrsReps           int            `gorm:"type:smallint unsigned;column:wtrs_reps" json:"wtrs_reps"`
	WtrsWeight         float64        `gorm:"type:decimal(5,2);column:wtrs_weight" json:"wtrs_weight"`
	// *int เพราะคอลัมน์ nullable จริง (เพิ่มเข้ามา 2026-09-08 — แถวเก่าก่อนหน้านั้นเป็น NULL หมด)
	// เหตุผลเดียวกับ WetID/WschID ด้านล่าง: ประกาศเป็น int เฉยๆ GORM scan NULL ไม่ได้
	// เวลาออกแรงจริงของเซตนี้ (วินาที) — เก็บไว้เป็นหลักฐานตรวจสอบย้อนหลังเท่านั้น
	// CalculateWeightTrainingCalories ไม่ได้อ่านค่านี้ ใช้ WtrsDuration (เวลารวมทั้งเซสชัน) เป็นฐานเวลา
	WtrsActiveSeconds *int `gorm:"type:smallint unsigned;column:wtrs_active_seconds" json:"wtrs_active_seconds"`
	// เวลารวมทั้งเซสชัน (วินาที) ซ้ำกันทุกแถวของเซสชันเดียวกัน — ห้าม SUM ข้ามแถว
	WtrsDuration       *int           `gorm:"type:smallint unsigned;column:wtrs_duration" json:"wtrs_duration"`
	WtrsIntensityLevel int8           `gorm:"type:tinyint;column:wtrs_intensity_level" json:"wtrs_intensity_level"` // 1=เบา, 2=กลาง, 3=หนัก — ตั้งแต่ 2026-09-08 ระบบอนุมานเองจาก %1RM ไม่ใช่ผู้ใช้เลือก
	WtrsCalories       float64        `gorm:"type:decimal(6,2);column:wtrs_calories" json:"wtrs_calories"`
	MbID               uint           `gorm:"type:int(11);column:mb_id;not null" json:"mb_id"`
	// WetID เป็น *uint เพราะคอลัมน์ wet_id เป็น nullable จริงใน DB (FK ON DELETE SET NULL) ถ้า
	// ประกาศเป็น uint เฉยๆ GORM จะ scan NULL ไม่ได้แล้วพังทั้ง endpoint ที่อ่านประวัติ (2026-09-06)
	//
	// แก้คำอธิบายเดิม (2026-09-06 รอบ 2): เดิมเขียนว่า "แอดมินลบท่าฝึกได้โดยไม่ทำประวัติการฝึกหาย"
	// ซึ่งไม่ตรงกับของจริง — DeleteWeightExercise บล็อกการลบตั้งแต่ต้นถ้ามีแถวใน
	// weight_training_result อ้างอิงอยู่ (ตอบ 400) ทาง SET NULL จึงไม่มีวันถูกยิงจากแอปเลย
	// เหลือทางเดียวคือลบด้วย SQL ตรงผ่าน phpMyAdmin/CLI ซึ่ง bypass ด่านฝั่ง Go — *uint ยังจำเป็น
	// อยู่เพื่อกันเคสนั้นกับข้อมูลเก่าที่อาจมี NULL ค้าง ไม่ใช่เพราะแอปตั้งใจให้ลบได้
	WetID              *uint          `gorm:"type:int unsigned;column:wet_id" json:"wet_id"`
	WschID             *uint          `gorm:"type:int unsigned;column:wsch_id" json:"wsch_id"`
	WeightExercise     WeightExercise `gorm:"foreignKey:WetID;references:WetID" json:"weight_exercise"`
}

func (WeightTrainingResult) TableName() string {
	return "weight_training_result"
}

// 11. ตารางผลการคาร์ดิโอ (Cardio Result) - ผู้ใช้เลือกทำเองโดยไม่มีตารางฝึก
type CardioResult struct {
	CdorsID       uint    `gorm:"primaryKey;column:cdors_id;autoIncrement" json:"cdors_id"`
	CdorsDate     string  `gorm:"type:date;column:cdors_date;not null" json:"cdors_date"`
	CdorsDuration int     `gorm:"type:smallint unsigned;column:cdors_duration" json:"cdors_duration"`
	// CdorsDistance เป็น *float64 และไม่มี DEFAULT แล้ว (2026-09-06) — NULL = กิจกรรมนี้ไม่วัด
	// ระยะทาง (cdo_has_distance = 0) ซึ่งคนละความหมายกับ 0.00 (วิ่งได้ 0 กม.) ที่ DEFAULT เดิมให้มา
	CdorsDistance *float64 `gorm:"type:decimal(5,2);column:cdors_distance" json:"cdors_distance"`
	CdorsCalories float64 `gorm:"type:decimal(6,2);column:cdors_calories" json:"cdors_calories"`
	MbID          uint    `gorm:"type:int(11);column:mb_id;not null" json:"mb_id"`
	// CdoID เป็น *uint ด้วยเหตุผลเดียวกับ WeightTrainingResult.WetID ด้านบน (FK ON DELETE SET NULL)
	CdoID         *uint   `gorm:"type:int unsigned;column:cdo_id" json:"cdo_id"`
	CardioType    Cardio  `gorm:"foreignKey:CdoID;references:CdoID" json:"cardio_type"`
}

func (CardioResult) TableName() string {
	return "cardio_result"
}
