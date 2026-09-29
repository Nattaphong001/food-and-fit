package controllers

import (
	"fmt"
	"log/slog"
	"net/http"
	"strconv"

	"food_and_fit_api/config"
	"food_and_fit_api/helpers"
	"food_and_fit_api/models"

	"github.com/gin-gonic/gin"
)

// ==========================================
// ส่วนที่ 1: จัดการกลุ่มกล้ามเนื้อ (Muscle Group)
// ==========================================

func GetMuscleGroups(c *gin.Context) {
	var muscles []models.MuscleGroup
	config.DB.Find(&muscles)
	c.JSON(http.StatusOK, gin.H{"data": muscles})
}

// 🟢 อัปเดต: รองรับการรับไฟล์รูปภาพ (Multipart Form)
func CreateMuscleGroup(c *gin.Context) {
	// 1. รับค่าที่เป็น Text จาก Form
	mugName := c.PostForm("mug_name")
	mugZoneStr := c.PostForm("mug_zone")

	// แปลง String เป็น Int
	mugZone, _ := strconv.Atoi(mugZoneStr)
	if ok, msg := helpers.ValidateMuscleGroupZone(mugZone); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	// กำหนดรูปเริ่มต้น
	imagePath := "images/default.png"

	// 2. รับค่าที่เป็น File
	if file, ferr := c.FormFile("mug_image"); ferr == nil {
		newPath, verr := helpers.SaveUploadedImage(c, file, "./uploads/muscle_groups", "uploads/muscle_groups")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			// เก็บ Path สำหรับลง Database
			imagePath = newPath
		}
	}

	// 3. บันทึกลง Database (อิงตามชื่อ Field ใน Struct ของคุณ)
	// *หมายเหตุ: ตรวจสอบชื่อตัวแปร MugName, MugZone, MugImage ให้ตรงกับที่กำหนดไว้ใน models.MuscleGroup
	muscle := models.MuscleGroup{
		MugName:  mugName,
		MugZone:  int8(mugZone), // #nosec G115 -- validated by ValidateMuscleGroupZone (1-3) above
		MugImage: imagePath,
	}

	if err := config.DB.Create(&muscle).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีกลุ่มกล้ามเนื้อชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกข้อมูลไม่สำเร็จ"})
		return
	}

	helpers.LogAdminMutation(c, "create", "muscle_group", muscle.MugID, nil, muscle)
	c.JSON(http.StatusOK, gin.H{"message": "เพิ่มสำเร็จ", "data": muscle})
}

// 🟢 อัปเดต: รองรับการแก้ไขข้อมูลพร้อมรูปภาพใหม่
func UpdateMuscleGroup(c *gin.Context) {
	id := c.Param("id")
	var muscle models.MuscleGroup

	// ค้นหาข้อมูลเดิมก่อน
	if err := config.DB.First(&muscle, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูล"})
		return
	}
	before := muscle // snapshot ก่อนแก้ ไว้ให้ audit log (S-9 old_value)

	// อัปเดตข้อมูล Text
	if mugName := c.PostForm("mug_name"); mugName != "" {
		muscle.MugName = mugName
	}
	if mugZoneStr := c.PostForm("mug_zone"); mugZoneStr != "" {
		mugZone, _ := strconv.Atoi(mugZoneStr)
		if ok, msg := helpers.ValidateMuscleGroupZone(mugZone); !ok {
			c.JSON(http.StatusBadRequest, gin.H{"error": msg})
			return
		}
		muscle.MugZone = int8(mugZone) // #nosec G115 -- validated by ValidateMuscleGroupZone (1-3) above
	}

	// จัดการรูปภาพ (ถ้ามีการส่งไฟล์ใหม่มา)
	if file, ferr := c.FormFile("mug_image"); ferr == nil {
		newPath, verr := helpers.SaveUploadedImage(c, file, "./uploads/muscle_groups", "uploads/muscle_groups")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			// ลบไฟล์เก่าทิ้งเพื่อประหยัดพื้นที่ (ถ้าไม่ใช่ไฟล์ default)
			if muscle.MugImage != "" && muscle.MugImage != "images/default.png" {
				helpers.RemoveOldFile("./" + muscle.MugImage)
			}
			// อัปเดต Path เป็นรูปใหม่
			muscle.MugImage = newPath
		}
	}

	// บันทึกการแก้ไข
	if err := config.DB.Save(&muscle).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีกลุ่มกล้ามเนื้อชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "แก้ไขข้อมูลไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "muscle_group", muscle.MugID, before, muscle)
	c.JSON(http.StatusOK, gin.H{"message": "แก้ไขสำเร็จ", "data": muscle})
}

func DeleteMuscleGroup(c *gin.Context) {
	id := c.Param("id")

	// เดิมเช็คจาก weight_exercises.mug_id ตรงๆ — คอลัมน์นั้นถูก DROP ออกจาก DB แล้ว (2026-09-04)
	// เช็คการใช้งานจริงผ่าน exercise_muscle_details แทน (ตารางเดียวที่ยังผูก mug_id อยู่)
	var count int64
	config.DB.Model(&models.ExerciseMuscleDetail{}).Where("mug_id = ?", id).Count(&count)
	if count > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบได้ เพราะมีท่าออกกำลังกาย %d ท่าที่ใช้กลุ่มกล้ามเนื้อนี้อยู่", count)})
		return
	}

	var muscle models.MuscleGroup
	if err := config.DB.First(&muscle, id).Error; err == nil {
		if muscle.MugImage != "" && muscle.MugImage != "images/default.png" {
			helpers.RemoveOldFile("./" + muscle.MugImage)
		}
	}

	config.DB.Delete(&models.MuscleGroup{}, id)
	helpers.LogAdminMutation(c, "delete", "muscle_group", id, muscle, nil)
	c.JSON(http.StatusOK, gin.H{"message": "ลบสำเร็จ"})
}

// ==========================================
// ส่วนที่ 2: จัดการท่าเวทเทรนนิ่ง (Weight Exercises)
// ==========================================

func GetWeightExercises(c *gin.Context) {
	var exercises []models.WeightExercise
	config.DB.Preload("MuscleDetails.MuscleGroup").Order("wet_id ASC").Find(&exercises)
	c.JSON(http.StatusOK, gin.H{"data": exercises})
}

// 🟢 อัปเดต: รองรับการรับไฟล์รูปภาพ (Multipart Form)
func CreateWeightExercise(c *gin.Context) {
	// 1. รับค่าที่เป็น Text จาก Form
	wetName := c.PostForm("wet_name")
	wetDesc := c.PostForm("wet_description")
	wetTechnique := c.PostForm("wet_technique")
	wetVideo := c.PostForm("wet_video")
	if verr := helpers.ValidateTutorialVideoURL(wetVideo); verr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
		return
	}
	wetDiff, _ := strconv.Atoi(c.PostForm("wet_difficulty"))
	wetEquip, _ := strconv.Atoi(c.PostForm("wet_equipment"))
	if wetEquip == 0 {
		wetEquip = 5 // default Bodyweight
	}
	wetExerciseType, _ := strconv.Atoi(c.PostForm("wet_exercise_type"))
	if wetExerciseType == 0 {
		wetExerciseType = 1 // default Compound
	}
	if ok, msg := helpers.ValidateWeightExerciseCodes(wetDiff, wetEquip, wetExerciseType); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	// wet_mets — METs คงที่ของท่านี้ (2024 Adult Compendium of Physical Activities, Herrmann et al.,
	// 2567) ช่วงตรวจเดียวกับ cdo_mets ของ cardio ค่าเริ่มต้น 3.5 ถ้าไม่ได้ส่งมา (ตรงกับ DB default)
	wetMets := 3.5
	if metsStr := c.PostForm("wet_mets"); metsStr != "" {
		m, metsErr := strconv.ParseFloat(metsStr, 64)
		if metsErr != nil || m < 0.9 || m > 25 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "ค่า METs ต้องเป็นตัวเลขระหว่าง 0.9-25"})
			return
		}
		wetMets = m
	}
	// mug_id (ถ้า form ส่งมา) ไม่ใช้แล้ว — weight_exercises.mug_id ถูก DROP ออกจาก DB (2026-09-04)
	// กำหนดกล้ามเนื้อของท่าฝึกผ่าน endpoint exercise_muscle_details แยกต่างหากเท่านั้น (รองรับ
	// หลักหลายมัด/รองได้ ต่างจาก mug_id เดิมที่เก็บได้แค่มัดเดียว)

	// กำหนดรูปเริ่มต้น
	imagePath := ""

	// 2. รับค่าที่เป็น File
	if file, ferr := c.FormFile("wet_image"); ferr == nil {
		newPath, verr := helpers.SaveUploadedImage(c, file, "./uploads/weight_exercises/image", "uploads/weight_exercises/image")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			imagePath = newPath
		}
	}

	// Loop video upload
	loopVideoPath := ""
	if loopFile, lferr := c.FormFile("wet_loop_video"); lferr == nil {
		newPath, verr := helpers.SaveUploadedVideo(c, loopFile, "./uploads/weight_exercises/videoloop", "uploads/weight_exercises/videoloop")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			loopVideoPath = newPath
		}
	}

	// 3. บันทึกลง Database
	exercise := models.WeightExercise{
		WetName:         wetName,
		WetDescription:  wetDesc,
		WetTechnique:    wetTechnique,
		WetVideo:        wetVideo,
		WetLoopVideo:    loopVideoPath,
		WetDifficulty:   int8(wetDiff),         // #nosec G115 -- validated by ValidateWeightExerciseCodes above
		WetEquipment:    int8(wetEquip),        // #nosec G115 -- validated by ValidateWeightExerciseCodes above
		WetExerciseType: int8(wetExerciseType), // #nosec G115 -- validated by ValidateWeightExerciseCodes above
		WetMets:         wetMets,
		WetImage:        imagePath,
	}

	if err := config.DB.Create(&exercise).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีท่าฝึกชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "create", "weight_exercises", exercise.WetID, nil, exercise)
	c.JSON(http.StatusCreated, gin.H{"message": "เพิ่มท่าสำเร็จ", "data": exercise})
}

// 🟢 อัปเดต: รองรับการแก้ไขข้อมูลพร้อมรูปภาพใหม่
func UpdateWeightExercise(c *gin.Context) {
	id := c.Param("id")
	var exercise models.WeightExercise

	// ค้นหาข้อมูลเดิมก่อน
	if err := config.DB.First(&exercise, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบท่าฝึก"})
		return
	}
	before := exercise // snapshot ก่อนแก้ ไว้ให้ audit log (S-9 old_value)

	// อัปเดตข้อมูล Text
	if name := c.PostForm("wet_name"); name != "" {
		exercise.WetName = name
	}
	if desc := c.PostForm("wet_description"); desc != "" {
		exercise.WetDescription = desc
	}
	exercise.WetTechnique = c.PostForm("wet_technique")
	wetVideo := c.PostForm("wet_video")
	if verr := helpers.ValidateTutorialVideoURL(wetVideo); verr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
		return
	}
	exercise.WetVideo = wetVideo
	// เดิม 3 จุดนี้ Atoi แล้ว cast เป็น int8 ตรงๆ ไม่เช็คช่วงเหมือนฝั่ง Create (ที่มี
	// ValidateWeightExerciseCodes กันอยู่แล้ว) — ค่านอกช่วง (เช่นพิมพ์ "300") จะ wrap เงียบๆ กลาย
	// เป็นเลขผิดแทนที่จะ error (gosec G115) เพิ่มเช็คช่วงเดียวกับ Create ให้ตรงกัน
	if diffStr := c.PostForm("wet_difficulty"); diffStr != "" {
		diff, err := strconv.Atoi(diffStr)
		if err != nil || diff < 1 || diff > 3 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "ระดับความยากต้องเป็น 1, 2 หรือ 3 เท่านั้น"})
			return
		}
		exercise.WetDifficulty = int8(diff)
	}
	if equipStr := c.PostForm("wet_equipment"); equipStr != "" {
		equip, err := strconv.Atoi(equipStr)
		if err != nil || equip < 1 || equip > 5 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "อุปกรณ์ต้องเป็นค่า 1-5 เท่านั้น"})
			return
		}
		exercise.WetEquipment = int8(equip)
	}
	if typeStr := c.PostForm("wet_exercise_type"); typeStr != "" {
		t, err := strconv.Atoi(typeStr)
		if err != nil || t < 1 || t > 2 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "ประเภทท่าฝึกต้องเป็น 1 หรือ 2 เท่านั้น"})
			return
		}
		exercise.WetExerciseType = int8(t)
	}
	if metsStr := c.PostForm("wet_mets"); metsStr != "" {
		m, metsErr := strconv.ParseFloat(metsStr, 64)
		if metsErr != nil || m < 0.9 || m > 25 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "ค่า METs ต้องเป็นตัวเลขระหว่าง 0.9-25"})
			return
		}
		exercise.WetMets = m
	}
	// mug_id (ถ้า form ส่งมา) ไม่ใช้แล้ว — เหตุผลเดียวกับ CreateWeightExercise ด้านบน

	if ok, msg := helpers.ValidateWeightExerciseCodes(int(exercise.WetDifficulty), int(exercise.WetEquipment), int(exercise.WetExerciseType)); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	// จัดการรูปภาพ (ถ้ามีการส่งไฟล์ใหม่มา)
	if file, ferr := c.FormFile("wet_image"); ferr == nil {
		newPath, verr := helpers.SaveUploadedImage(c, file, "./uploads/weight_exercises/image", "uploads/weight_exercises/image")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			if exercise.WetImage != "" {
				helpers.RemoveOldFile("./" + exercise.WetImage)
			}
			exercise.WetImage = newPath
		}
	}

	// Loop video upload
	if loopVideoFile, lferr := c.FormFile("wet_loop_video"); lferr == nil {
		newPath, verr := helpers.SaveUploadedVideo(c, loopVideoFile, "./uploads/weight_exercises/videoloop", "uploads/weight_exercises/videoloop")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			if exercise.WetLoopVideo != "" {
				helpers.RemoveOldFile("./" + exercise.WetLoopVideo)
			}
			exercise.WetLoopVideo = newPath
		}
	}

	// บันทึกการแก้ไข
	if err := config.DB.Save(&exercise).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีท่าฝึกชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "แก้ไขไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "weight_exercises", exercise.WetID, before, exercise)
	c.JSON(http.StatusOK, gin.H{"message": "แก้ไขท่าสำเร็จ", "data": exercise})
}

func DeleteWeightExercise(c *gin.Context) {
	id := c.Param("id")

	var planCount int64
	config.DB.Model(&models.PlanTemplateDetail{}).Where("wet_id = ?", id).Count(&planCount)
	if planCount > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบได้ เพราะท่านี้ถูกใช้ใน %d แผนการฝึก กรุณาลบออกจากแผนก่อน", planCount)})
		return
	}

	var resultCount int64
	config.DB.Model(&models.WeightTrainingResult{}).Where("wet_id = ?", id).Count(&resultCount)
	if resultCount > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบได้ เพราะมีผลการฝึกของสมาชิก %d รายการที่อ้างอิงท่านี้อยู่", resultCount)})
		return
	}

	// (2026-09-06) เพิ่มด่านที่ 3: แผนส่วนตัวของสมาชิก (workout_schedules) — เดิมเช็คแค่แผนแม่แบบระบบ
	// (plan_template_detail) กับประวัติผลฝึก (weight_training_result) ทำให้ท่าที่สมาชิกใส่ไว้ในแผน
	// ตัวเองแต่ยังไม่เคยบันทึกผล ผ่านทั้ง 2 ด่านแรกและถูกลบได้ — FK fk_wsch_exercise เป็น
	// ON DELETE CASCADE (ไม่ใช่ SET NULL เหมือนอีก 2 ตาราง) แถวท่าฝึกในแผนสมาชิกจึงหายเงียบๆ
	// ตามไปด้วยโดยไม่มีใครรู้ตัว (แถวหัวแผน wet_id IS NULL ไม่โดน CASCADE แผนไม่พังทั้งแผน)
	// นับเป็น "จำนวนสมาชิก" ไม่ใช่จำนวนแถว เพราะ 1 สมาชิกใส่ท่าเดียวกันได้หลายวันในแผนเดียว
	var memberPlanCount int64
	config.DB.Model(&models.WorkoutSchedule{}).Where("wet_id = ?", id).Distinct("mb_id").Count(&memberPlanCount)
	if memberPlanCount > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบได้ เพราะท่านี้อยู่ในแผนการฝึกส่วนตัวของสมาชิก %d คน กรุณาให้สมาชิกลบออกจากแผนก่อน", memberPlanCount)})
		return
	}

	var exercise models.WeightExercise
	if err := config.DB.First(&exercise, id).Error; err == nil {
		if exercise.WetImage != "" {
			helpers.RemoveOldFile("./" + exercise.WetImage)
		}
		if exercise.WetLoopVideo != "" {
			helpers.RemoveOldFile("./" + exercise.WetLoopVideo)
		}
	}

	config.DB.Delete(&models.WeightExercise{}, id)
	helpers.LogAdminMutation(c, "delete", "weight_exercises", id, exercise, nil)
	c.JSON(http.StatusOK, gin.H{"message": "ลบท่าฝึกสำเร็จ"})
}

// ==========================================
// ส่วนที่ 3: จัดการการเชื่อมโยง (Exercise Muscle Details)
// ==========================================

func GetExerciseMuscleDetails(c *gin.Context) {
	var results []map[string]interface{}

	query := `
		SELECT
			emd.emd_id as id,
			emd.wet_id as wet_id,
			emd.mug_id as mug_id,
			we.wet_name as exercise,
			mg.mug_name as muscle,
			IF(emd.exm_type = 1, 'หลัก', 'รอง') as type,
			emd.exm_type as exm_type
		FROM exercise_muscle_details emd
		JOIN weight_exercises we ON emd.wet_id = we.wet_id
		JOIN muscle_group mg ON emd.mug_id = mg.mug_id
	`

	args := []interface{}{}
	if wetID := c.Query("wet_id"); wetID != "" {
		query += " WHERE emd.wet_id = ?"
		args = append(args, wetID)
	}
	query += " ORDER BY emd.exm_type ASC"

	if err := config.DB.Raw(query, args...).Scan(&results).Error; err != nil {
		slog.Error("GetExerciseMuscleDetails: query failed", "err", err, "request_id", c.GetString("request_id"))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถดึงข้อมูลได้ กรุณาลองใหม่"})
		return
	}
	c.JSON(200, gin.H{"data": results})
}

func CreateExerciseMuscleDetail(c *gin.Context) {
	var input struct {
		ExmType int `json:"exm_type"`
		WetID   int `json:"wet_id"`
		MugID   int `json:"mug_id"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง"})
		return
	}

	sql := "INSERT INTO exercise_muscle_details (exm_type, wet_id, mug_id) VALUES (?, ?, ?)"
	if err := config.DB.Exec(sql, input.ExmType, input.WetID, input.MugID).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "ท่านี้ผูกกับกล้ามเนื้อกลุ่มนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถบันทึกข้อมูลได้"})
		return
	}

	helpers.LogAdminMutation(c, "create", "exercise_muscle_details", fmt.Sprintf("wet_id=%d,mug_id=%d", input.WetID, input.MugID), nil, input)
	c.JSON(http.StatusOK, gin.H{"message": "เชื่อมโยงข้อมูลสำเร็จ"})
}

func DeleteExerciseMuscleDetail(c *gin.Context) {
	id := c.Param("id")

	var before models.ExerciseMuscleDetail
	config.DB.First(&before, id) // best-effort snapshot ก่อนลบ ไว้ให้ audit log (ไม่ block ถ้าหาไม่เจอ)

	if err := config.DB.Exec("DELETE FROM exercise_muscle_details WHERE emd_id = ?", id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ลบข้อมูลไม่สำเร็จ"})
		return
	}

	helpers.LogAdminMutation(c, "delete", "exercise_muscle_details", id, before, nil)
	c.JSON(http.StatusOK, gin.H{"message": "ลบข้อมูลสำเร็จ"})
}

func UpdateExerciseMuscleDetail(c *gin.Context) {
	id := c.Param("id")
	var input struct {
		ExmType int `json:"exm_type"`
		WetID   int `json:"wet_id"`
		MugID   int `json:"mug_id"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(400, gin.H{"error": "ข้อมูลไม่ถูกต้อง"})
		return
	}

	var before models.ExerciseMuscleDetail
	config.DB.First(&before, id) // snapshot ก่อนแก้ ไว้ให้ audit log

	sql := "UPDATE exercise_muscle_details SET exm_type = ?, wet_id = ?, mug_id = ? WHERE emd_id = ?"
	if err := config.DB.Exec(sql, input.ExmType, input.WetID, input.MugID, id).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "ท่านี้ผูกกับกล้ามเนื้อกลุ่มนี้อยู่แล้ว"})
			return
		}
		c.JSON(500, gin.H{"error": "แก้ไขข้อมูลไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "exercise_muscle_details", id, before, input)
	c.JSON(200, gin.H{"message": "แก้ไขสำเร็จ"})
}

// ==========================================
// ส่วนที่ 4: จัดการกิจกรรมคาร์ดิโอ (Cardio)
// ==========================================

func GetCardioExercises(c *gin.Context) {
	var cardioList []models.Cardio
	if err := config.DB.Order("cdo_id ASC").Find(&cardioList).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถดึงข้อมูลคาร์ดิโอได้"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": cardioList})
}

// 🟢 อัปเดต: รองรับการรับไฟล์รูปภาพ (Multipart Form)
func CreateCardioExercise(c *gin.Context) {
	// 1. รับค่า Text จาก Form
	cdoName := c.PostForm("cdo_name")
	cdoMetsStr := c.PostForm("cdo_mets")
	cdoDesc := c.PostForm("cdo_description")
	cdoTechnique := c.PostForm("cdo_technique")
	cdoVideo := c.PostForm("cdo_video")
	if verr := helpers.ValidateTutorialVideoURL(cdoVideo); verr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
		return
	}
	cdcIDStr := c.PostForm("cdc_id")

	cdoMets, metsErr := strconv.ParseFloat(cdoMetsStr, 64)
	if metsErr != nil || cdoMets < 0.9 || cdoMets > 25 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ค่า METs ต้องเป็นตัวเลขระหว่าง 0.9-25"})
		return
	}
	cdcID, _ := strconv.Atoi(cdcIDStr)
	cdoHasDistance, _ := strconv.Atoi(c.PostForm("cdo_has_distance"))
	if cdoHasDistance != 0 && cdoHasDistance != 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cdo_has_distance ต้องเป็น 0 หรือ 1 เท่านั้น"})
		return
	}
	// เช็ค cdc_id มีอยู่จริงก่อน insert กันชน FK constraint แบบ error ดิบ (เดิมไม่เช็ค ถ้า client
	// ไม่ส่ง cdc_id มา strconv.Atoi("") ได้ 0 เงียบๆ แล้วไปพังตอน insert เป็น FK violation แทน)
	var cdcCount int64
	config.DB.Model(&models.CardioCategory{}).Where("cdc_id = ?", cdcID).Count(&cdcCount)
	if cdcCount == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาเลือกหมวดหมู่คาร์ดิโอให้ถูกต้อง"})
		return
	}

	// 2. รับและบันทึกไฟล์รูปภาพ
	imagePath := ""
	if file, ferr := c.FormFile("cdo_image"); ferr == nil {
		newPath, verr := helpers.SaveUploadedImage(c, file, "./uploads/cardio/images", "uploads/cardio/images")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			imagePath = newPath
		}
	}

	// Loop video upload
	loopVideoPath := ""
	if loopFile, lferr := c.FormFile("cdo_loop_video"); lferr == nil {
		newPath, verr := helpers.SaveUploadedVideo(c, loopFile, "./uploads/cardio/videoloop", "uploads/cardio/videoloop")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			loopVideoPath = newPath
		}
	}

	// 3. บันทึกลง Database
	cardio := models.Cardio{
		CdoName:        cdoName,
		CdoMets:        cdoMets,
		CdoDescription: cdoDesc,
		CdoTechnique:   cdoTechnique,
		CdoVideo:       cdoVideo,
		CdoImage:       imagePath,
		CdoLoopVideo:   loopVideoPath,
		CdoHasDistance: int8(cdoHasDistance), // #nosec G115 -- validated as 0/1 above
		CdcID:          uint(cdcID),
	}

	if err := config.DB.Create(&cardio).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีกิจกรรมคาร์ดิโอชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "create", "cardio", cardio.CdoID, nil, cardio)
	c.JSON(http.StatusCreated, gin.H{"message": "เพิ่มข้อมูลคาร์ดิโอสำเร็จ", "data": cardio})
}

// 🟢 อัปเดต: รองรับการแก้ไขข้อมูลพร้อมรูปภาพใหม่
func UpdateCardioExercise(c *gin.Context) {
	id := c.Param("id")
	var cardio models.Cardio

	// ค้นหาข้อมูลเดิมก่อน
	if err := config.DB.First(&cardio, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูลคาร์ดิโอ"})
		return
	}
	before := cardio // snapshot ก่อนแก้ ไว้ให้ audit log (S-9 old_value)

	// อัปเดตข้อมูล Text
	if name := c.PostForm("cdo_name"); name != "" {
		cardio.CdoName = name
	}
	if metsStr := c.PostForm("cdo_mets"); metsStr != "" {
		mets, metsErr := strconv.ParseFloat(metsStr, 64)
		if metsErr != nil || mets < 0.9 || mets > 25 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "ค่า METs ต้องเป็นตัวเลขระหว่าง 0.9-25"})
			return
		}
		cardio.CdoMets = mets
	}
	if desc := c.PostForm("cdo_description"); desc != "" {
		cardio.CdoDescription = desc
	}
	cardio.CdoTechnique = c.PostForm("cdo_technique")
	cdoVideo := c.PostForm("cdo_video")
	if verr := helpers.ValidateTutorialVideoURL(cdoVideo); verr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
		return
	}
	cardio.CdoVideo = cdoVideo
	if cdcStr := c.PostForm("cdc_id"); cdcStr != "" {
		cdcID, _ := strconv.Atoi(cdcStr)
		var cdcCount int64
		config.DB.Model(&models.CardioCategory{}).Where("cdc_id = ?", cdcID).Count(&cdcCount)
		if cdcCount == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาเลือกหมวดหมู่คาร์ดิโอให้ถูกต้อง"})
			return
		}
		cardio.CdcID = uint(cdcID)
	}
	if distStr := c.PostForm("cdo_has_distance"); distStr != "" {
		d, _ := strconv.Atoi(distStr)
		if d != 0 && d != 1 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "cdo_has_distance ต้องเป็น 0 หรือ 1 เท่านั้น"})
			return
		}
		cardio.CdoHasDistance = int8(d)
	}

	// จัดการรูปภาพใหม่ (ถ้ามี)
	if file, ferr := c.FormFile("cdo_image"); ferr == nil {
		newPath, verr := helpers.SaveUploadedImage(c, file, "./uploads/cardio/images", "uploads/cardio/images")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			if cardio.CdoImage != "" {
				helpers.RemoveOldFile("./" + cardio.CdoImage)
			}
			cardio.CdoImage = newPath
		}
	}

	// Loop video upload
	if loopFile, lferr := c.FormFile("cdo_loop_video"); lferr == nil {
		newPath, verr := helpers.SaveUploadedVideo(c, loopFile, "./uploads/cardio/videoloop", "uploads/cardio/videoloop")
		if verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		if newPath != "" {
			if cardio.CdoLoopVideo != "" {
				helpers.RemoveOldFile("./" + cardio.CdoLoopVideo)
			}
			cardio.CdoLoopVideo = newPath
		}
	}

	// บันทึกการแก้ไข
	if err := config.DB.Save(&cardio).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีกิจกรรมคาร์ดิโอชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "แก้ไขไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "cardio", cardio.CdoID, before, cardio)
	c.JSON(http.StatusOK, gin.H{"message": "แก้ไขข้อมูลสำเร็จ", "data": cardio})
}

func DeleteCardioExercise(c *gin.Context) {
	id := c.Param("id")

	var count int64
	config.DB.Model(&models.CardioResult{}).Where("cdo_id = ?", id).Count(&count)
	if count > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบได้ เพราะมีผลการฝึกคาร์ดิโอของสมาชิก %d รายการที่อ้างอิงกิจกรรมนี้อยู่", count)})
		return
	}

	var cardio models.Cardio
	if err := config.DB.First(&cardio, id).Error; err == nil {
		if cardio.CdoImage != "" {
			helpers.RemoveOldFile("./" + cardio.CdoImage)
		}
	}

	config.DB.Delete(&models.Cardio{}, id)
	helpers.LogAdminMutation(c, "delete", "cardio", id, cardio, nil)
	c.JSON(http.StatusOK, gin.H{"message": "ลบข้อมูลสำเร็จ"})
}

func GetCardioCategories(c *gin.Context) {
	var categories []models.CardioCategory
	config.DB.Find(&categories)
	c.JSON(http.StatusOK, gin.H{"data": categories})
}

// cardioCategoryInput คือ DTO รับเฉพาะ field ที่แก้ไขได้จริง — ไม่ bind ตรงเข้า models.CardioCategory
// เพราะ struct นั้นมี cdc_id ด้วย ถ้า client ส่ง cdc_id มาใน body จะเขียนทับ primary key ที่ตั้งใจแก้
// (mass assignment / มี "id" ปนกับ URL :id ได้ ผลลัพธ์ไม่แน่นอน)
type cardioCategoryInput struct {
	CdcName        string `json:"cdc_name"`
	CdcDescription string `json:"cdc_description"`
}

func CreateCardioCategory(c *gin.Context) {
	var input cardioCategoryInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง"})
		return
	}
	category := models.CardioCategory{CdcName: input.CdcName, CdcDescription: input.CdcDescription}
	if err := config.DB.Create(&category).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีประเภทคาร์ดิโอชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "เพิ่มหมวดหมู่ไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "create", "cardio_category", category.CdcID, nil, category)
	c.JSON(http.StatusOK, gin.H{"message": "เพิ่มหมวดหมู่สำเร็จ", "data": category})
}

func UpdateCardioCategory(c *gin.Context) {
	id := c.Param("id")
	var category models.CardioCategory
	if err := config.DB.First(&category, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูล"})
		return
	}
	before := category // snapshot ก่อนแก้ ไว้ให้ audit log (S-9 old_value)
	var input cardioCategoryInput
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง"})
		return
	}
	category.CdcName = input.CdcName
	category.CdcDescription = input.CdcDescription
	if err := config.DB.Save(&category).Error; err != nil {
		if helpers.IsDuplicateKeyError(err) {
			c.JSON(http.StatusConflict, gin.H{"error": "มีประเภทคาร์ดิโอชื่อนี้อยู่แล้ว"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "แก้ไขไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "cardio_category", category.CdcID, before, category)
	c.JSON(http.StatusOK, gin.H{"message": "แก้ไขสำเร็จ", "data": category})
}

// UpdateCardioCategoryImage อัปโหลด/แทนที่รูปหมวดหมู่คาร์ดิโอ — แยกเป็นคนละ endpoint จาก
// UpdateCardioCategory (JSON) ตั้งใจไม่รวมกัน เพราะ endpoint เดิมแอปมือถือส่ง JSON อยู่แล้ว
// เปลี่ยน content-type เป็น multipart จะกระทบของเดิม — เพิ่ง sync คอลัมน์ cdc_image ใหม่
func UpdateCardioCategoryImage(c *gin.Context) {
	id := c.Param("id")
	var category models.CardioCategory
	if err := config.DB.First(&category, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบข้อมูล"})
		return
	}
	before := category

	file, err := c.FormFile("cdc_image")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาแนบไฟล์รูปภาพ (cdc_image)"})
		return
	}
	newPath, verr := helpers.SaveUploadedImage(c, file, "./uploads/cardio_categories", "uploads/cardio_categories")
	if verr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
		return
	}
	if newPath == "" {
		// validate ผ่านแต่บันทึกไฟล์จริงล้มเหลว — เอนด์พอยต์นี้บังคับต้องมีไฟล์เสมอ (ต่างจากจุดอื่น
		// ที่ยอมให้เงียบๆ ได้เพราะไฟล์เป็น optional)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "อัปโหลดรูปไม่สำเร็จ"})
		return
	}
	if category.CdcImage != "" {
		helpers.RemoveOldFile("./" + category.CdcImage)
	}
	category.CdcImage = newPath

	if err := config.DB.Save(&category).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "บันทึกไม่สำเร็จ"})
		return
	}
	helpers.LogAdminMutation(c, "update", "cardio_category", category.CdcID, before, category)
	c.JSON(http.StatusOK, gin.H{"message": "อัปเดตรูปสำเร็จ", "data": category})
}

func DeleteCardioCategory(c *gin.Context) {
	id := c.Param("id")

	var count int64
	config.DB.Model(&models.Cardio{}).Where("cdc_id = ?", id).Count(&count)
	if count > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบได้ เพราะมีกิจกรรมคาร์ดิโอ %d รายการอยู่ในหมวดนี้ กรุณาย้ายหรือลบกิจกรรมก่อน", count)})
		return
	}

	var before models.CardioCategory
	config.DB.First(&before, id) // best-effort snapshot ก่อนลบ ไว้ให้ audit log

	config.DB.Delete(&models.CardioCategory{}, id)
	helpers.LogAdminMutation(c, "delete", "cardio_category", id, before, nil)
	c.JSON(http.StatusOK, gin.H{"message": "ลบข้อมูลสำเร็จ"})
}