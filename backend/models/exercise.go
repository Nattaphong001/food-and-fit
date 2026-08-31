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
type WeightExercise struct {
	WetID           uint        `gorm:"primaryKey;column:wet_id;autoIncrement" json:"wet_id"`
	WetName         string      `gorm:"type:varchar(100);column:wet_name" json:"wet_name"`
	WetDescription  string      `gorm:"type:text;column:wet_description" json:"wet_description"`
	WetTechnique    string      `gorm:"type:text;column:wet_technique" json:"wet_technique"`
	WetImage        string      `gorm:"type:varchar(255);column:wet_image" json:"wet_image"`
	WetVideo        string      `gorm:"type:varchar(255);column:wet_video" json:"wet_video"`
	WetLoopVideo    string      `gorm:"type:varchar(255);column:wet_loop_video" json:"wet_loop_video"`
	WetDifficulty   int8        `gorm:"type:tinyint;column:wet_difficulty" json:"wet_difficulty"`
	WetEquipment    int8        `gorm:"type:tinyint;column:wet_equipment;default:5" json:"wet_equipment"`
	WetExerciseType int8        `gorm:"type:tinyint;column:wet_exercise_type;default:1" json:"wet_exercise_type"` // 1=หลายกลุ่ม 2=เฉพาะส่วน
	MugID           *uint       `gorm:"column:mug_id" json:"mug_id"`
	MuscleGroup     MuscleGroup `gorm:"foreignKey:MugID;references:MugID" json:"muscle_group"`
}

func (WeightExercise) TableName() string {
	return "weight_exercises"
}

// 3. ตารางรายละเอียดกลุ่มกล้ามเนื้อในท่าฝึก (Exercise Muscle Details)
type ExerciseMuscleDetail struct {
	EmdID   uint `gorm:"primaryKey;column:emd_id;autoIncrement" json:"emd_id"`
	ExmType int8 `gorm:"type:tinyint;column:exm_type" json:"exm_type"` // 1=หลัก, 2=รอง
	WetID   uint `gorm:"column:wet_id" json:"wet_id"`
	MugID   uint `gorm:"column:mug_id" json:"mug_id"`
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
	PtdOrder       int            `gorm:"type:int;column:ptd_order;default:1" json:"ptd_order"`
	WeightExercise WeightExercise `gorm:"foreignKey:WetID;references:WetID" json:"weight_exercise"`
}

func (PlanTemplateDetail) TableName() string {
	return "plan_template_detail"
}

// Getters ด้านล่างมีไว้ให้ helpers.ValidatePlanTemplateDetail เรียกผ่าน interface กลาง
// (helpers ห้าม import models ตรงๆ เพราะ models ไม่ import helpers อยู่แล้ว แต่กันไว้ไม่ให้เกิด cycle ในอนาคต)
func (d PlanTemplateDetail) GetPtdDayNumber() int   { return d.PtdDayNumber }
func (d PlanTemplateDetail) GetPtdSets() int        { return d.PtdSets }
func (d PlanTemplateDetail) GetPtdReps() string     { return d.PtdReps }
func (d PlanTemplateDetail) GetPtdRestSeconds() int { return d.PtdRestSeconds }

// 8. ตารางฝึกเวทเทรนนิ่ง (Workout Schedules) — เก็บแผนที่ copy มาของผู้ใช้
// หมายเหตุ: type: tag ระบุชัดเจนกัน GORM AutoMigrate เดา type เป็น bigint แทน int ตาม default ของมัน
// wpt_id = แผนระบบ (ชี้ workout_plan_template, master data ร่วมทุกสมาชิก)
// mwp_id = แผนส่วนตัว (ชี้ member_workout_plans ของสมาชิกคนนั้นเอง) — มีค่าได้แค่ 1 ใน 2 (wpt_id/mwp_id) ต่อแถว
type WorkoutSchedule struct {
	WschID          uint           `gorm:"primaryKey;column:wsch_id;autoIncrement" json:"wsch_id"`
	WschDate        string         `gorm:"type:date;column:wsch_date" json:"wsch_date"`
	WschDayNumber   int            `gorm:"type:int;column:wsch_day_number;default:0" json:"wsch_day_number"`
	WschDayName     string         `gorm:"type:varchar(50);column:wsch_day_name" json:"wsch_day_name"`
	WschSets        int            `gorm:"type:int;column:wsch_sets;default:3" json:"wsch_sets"`
	WschRestSeconds int            `gorm:"type:int;column:wsch_rest_seconds;default:90" json:"wsch_rest_seconds"`
	WschReps        string         `gorm:"type:varchar(20);column:wsch_reps;default:'10'" json:"wsch_reps"`
	WschOrder       int            `gorm:"type:int;column:wsch_order;default:1" json:"wsch_order"`
	MbID            uint           `gorm:"type:int unsigned;column:mb_id" json:"mb_id"`
	WetID           uint           `gorm:"type:int unsigned;column:wet_id" json:"wet_id"`
	WptID           *uint          `gorm:"type:int unsigned;column:wpt_id" json:"wpt_id"`
	MwpID           *uint          `gorm:"type:int unsigned;column:mwp_id" json:"mwp_id"`
	WeightExercise  WeightExercise `gorm:"foreignKey:WetID;references:WetID" json:"weight_exercise"`
}

func (WorkoutSchedule) TableName() string {
	return "workout_schedules"
}

// 9. ตารางแผนส่วนตัวของสมาชิก (Member Workout Plans) — ต่างจาก workout_plan_template
//    ตรงที่นี่เป็นของสมาชิกแต่ละคนเอง (mb_id) แก้/ลบเองได้ ไม่ใช่ master data ที่แชร์ร่วมกัน
//    รองรับหลายแผนต่อสมาชิก 1 คน — แผนที่ "ใช้งานอยู่" ดูจาก member_profile.mb_active_mwp_id
type MemberWorkoutPlan struct {
	MwpID          uint      `gorm:"primaryKey;column:mwp_id;autoIncrement" json:"mwp_id"`
	MbID           uint      `gorm:"type:int;column:mb_id" json:"mb_id"`
	MwpName        string    `gorm:"type:varchar(100);column:mwp_name" json:"mwp_name"`
	MwpDaysPerWeek int       `gorm:"type:int;column:mwp_days_per_week;default:7" json:"mwp_days_per_week"`
	MwpCreatedAt   time.Time `gorm:"column:mwp_created_at;autoCreateTime" json:"mwp_created_at"`
}

func (MemberWorkoutPlan) TableName() string {
	return "member_workout_plans"
}

// 10. ตารางผลการฝึกเวท
// หมายเหตุ: ทุก type: tag ด้านล่างระบุไว้ชัดเจนเพื่อกัน GORM AutoMigrate เดา type เป็น bigint
// (ตาราง Datadic กำหนดเป็น INT ทั้งหมด — type: tag ด้านล่างต้องตรงกับ Datadic เสมอ)
type WeightTrainingResult struct {
	WtrsID             uint           `gorm:"primaryKey;column:wtrs_id;autoIncrement" json:"wtrs_id"`
	WtrsDate           string         `gorm:"type:date;column:wtrs_date" json:"wtrs_date"`
	WtrsSetNo          int            `gorm:"type:int;column:wtrs_set_no" json:"wtrs_set_no"`
	WtrsReps           int            `gorm:"type:int;column:wtrs_reps" json:"wtrs_reps"`
	WtrsWeight         float64        `gorm:"type:decimal(5,2);column:wtrs_weight" json:"wtrs_weight"`
	WtrsIntensityLevel int8           `gorm:"type:tinyint;column:wtrs_intensity_level;default:2" json:"wtrs_intensity_level"` // 1=เบา, 2=กลาง, 3=หนัก
	WtrsCalories       float64        `gorm:"type:decimal(7,2);column:wtrs_calories" json:"wtrs_calories"`
	MbID               uint           `gorm:"type:int unsigned;column:mb_id" json:"mb_id"`
	WetID              uint           `gorm:"type:int unsigned;column:wet_id" json:"wet_id"`
	WschID             *uint          `gorm:"type:int unsigned;column:wsch_id" json:"wsch_id"`
	WeightExercise     WeightExercise `gorm:"foreignKey:WetID;references:WetID" json:"weight_exercise"`
}

func (WeightTrainingResult) TableName() string {
	return "weight_training_result"
}

// 11. ตารางผลการคาร์ดิโอ (Cardio Result) - ผู้ใช้เลือกทำเองโดยไม่มีตารางฝึก
type CardioResult struct {
	CdorsID       uint    `gorm:"primaryKey;column:cdors_id;autoIncrement" json:"cdors_id"`
	CdorsDate     string  `gorm:"type:date;column:cdors_date" json:"cdors_date"`
	CdorsDuration int     `gorm:"type:int;column:cdors_duration" json:"cdors_duration"`
	CdorsDistance float64 `gorm:"type:decimal(5,2);column:cdors_distance;default:0" json:"cdors_distance"`
	CdorsCalories float64 `gorm:"type:decimal(7,2);column:cdors_calories" json:"cdors_calories"`
	MbID          uint    `gorm:"type:int unsigned;column:mb_id" json:"mb_id"`
	CdoID         uint    `gorm:"type:int unsigned;column:cdo_id" json:"cdo_id"`
	CardioType    Cardio  `gorm:"foreignKey:CdoID;references:CdoID" json:"cardio_type"`
}

func (CardioResult) TableName() string {
	return "cardio_result"
}
