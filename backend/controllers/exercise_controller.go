package controllers

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"

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
	file, err := c.FormFile("mug_image")
	if err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		// สร้างโฟลเดอร์ถ้ายังไม่มี
		uploadDir := "./uploads/muscle_groups"
		os.MkdirAll(uploadDir, os.ModePerm)

		// สร้างชื่อไฟล์ใหม่กันซ้ำ (ใช้ Timestamp)
		extension := filepath.Ext(file.Filename)
		newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
		savePath := filepath.Join(uploadDir, newFileName)

		// บันทึกไฟล์ลงเซิร์ฟเวอร์
		if err := c.SaveUploadedFile(file, savePath); err == nil {
			// เก็บ Path สำหรับลง Database
			imagePath = "uploads/muscle_groups/" + newFileName
		}
	}

	// 3. บันทึกลง Database (อิงตามชื่อ Field ใน Struct ของคุณ)
	// *หมายเหตุ: ตรวจสอบชื่อตัวแปร MugName, MugZone, MugImage ให้ตรงกับที่กำหนดไว้ใน models.MuscleGroup
	muscle := models.MuscleGroup{
		MugName:  mugName,
		MugZone:  int8(mugZone),
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
		muscle.MugZone = int8(mugZone)
	}

	// จัดการรูปภาพ (ถ้ามีการส่งไฟล์ใหม่มา)
	file, err := c.FormFile("mug_image")
	if err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		uploadDir := "./uploads/muscle_groups"
		os.MkdirAll(uploadDir, os.ModePerm)

		extension := filepath.Ext(file.Filename)
		newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
		savePath := filepath.Join(uploadDir, newFileName)

		if err := c.SaveUploadedFile(file, savePath); err == nil {
			// ลบไฟล์เก่าทิ้งเพื่อประหยัดพื้นที่ (ถ้าไม่ใช่ไฟล์ default)
			if muscle.MugImage != "" && muscle.MugImage != "images/default.png" {
				os.Remove("./" + muscle.MugImage)
			}
			// อัปเดต Path เป็นรูปใหม่
			muscle.MugImage = "uploads/muscle_groups/" + newFileName
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

	var count int64
	config.DB.Model(&models.WeightExercise{}).Where("mug_id = ?", id).Count(&count)
	if count > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("ไม่สามารถลบได้ เพราะมีท่าออกกำลังกาย %d ท่าที่ใช้กลุ่มกล้ามเนื้อนี้อยู่", count)})
		return
	}

	var muscle models.MuscleGroup
	if err := config.DB.First(&muscle, id).Error; err == nil {
		if muscle.MugImage != "" && muscle.MugImage != "images/default.png" {
			os.Remove("./" + muscle.MugImage)
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
	config.DB.Preload("MuscleGroup").Order("wet_id ASC").Find(&exercises)
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
	var mugID *uint
	if mugStr := c.PostForm("mug_id"); mugStr != "" {
		if v, err := strconv.ParseUint(mugStr, 10, 32); err == nil {
			u := uint(v)
			mugID = &u
		}
	}

	// กำหนดรูปเริ่มต้น
	imagePath := ""

	// 2. รับค่าที่เป็น File
	file, err := c.FormFile("wet_image")
	if err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		uploadDir := "./uploads/weight_exercises/image"
		os.MkdirAll(uploadDir, os.ModePerm)

		extension := filepath.Ext(file.Filename)
		newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
		savePath := filepath.Join(uploadDir, newFileName)

		if err := c.SaveUploadedFile(file, savePath); err == nil {
			imagePath = "uploads/weight_exercises/image/" + newFileName
		}
	}

	// Loop video upload
	loopVideoPath := ""
	loopFile, loopErr := c.FormFile("wet_loop_video")
	if loopErr == nil {
		if verr := helpers.ValidateVideoUpload(loopFile); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		loopDir := "./uploads/weight_exercises/videoloop"
		os.MkdirAll(loopDir, os.ModePerm)
		loopExt := filepath.Ext(loopFile.Filename)
		loopName := fmt.Sprintf("%d_loop%s", time.Now().UnixNano(), loopExt)
		loopPath := filepath.Join(loopDir, loopName)
		if err := c.SaveUploadedFile(loopFile, loopPath); err == nil {
			loopVideoPath = "uploads/weight_exercises/videoloop/" + loopName
		}
	}

	// 3. บันทึกลง Database
	exercise := models.WeightExercise{
		WetName:         wetName,
		WetDescription:  wetDesc,
		WetTechnique:    wetTechnique,
		WetVideo:        wetVideo,
		WetLoopVideo:    loopVideoPath,
		WetDifficulty:   int8(wetDiff),
		WetEquipment:    int8(wetEquip),
		WetExerciseType: int8(wetExerciseType),
		WetImage:        imagePath,
		MugID:           mugID,
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
	if diffStr := c.PostForm("wet_difficulty"); diffStr != "" {
		diff, _ := strconv.Atoi(diffStr)
		exercise.WetDifficulty = int8(diff)
	}
	if equipStr := c.PostForm("wet_equipment"); equipStr != "" {
		equip, _ := strconv.Atoi(equipStr)
		exercise.WetEquipment = int8(equip)
	}
	if typeStr := c.PostForm("wet_exercise_type"); typeStr != "" {
		t, _ := strconv.Atoi(typeStr)
		exercise.WetExerciseType = int8(t)
	}
	if mugStr := c.PostForm("mug_id"); mugStr != "" {
		if v, err := strconv.ParseUint(mugStr, 10, 32); err == nil {
			u := uint(v)
			exercise.MugID = &u
		}
	}

	if ok, msg := helpers.ValidateWeightExerciseCodes(int(exercise.WetDifficulty), int(exercise.WetEquipment), int(exercise.WetExerciseType)); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	// จัดการรูปภาพ (ถ้ามีการส่งไฟล์ใหม่มา)
	file, err := c.FormFile("wet_image")
	if err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		uploadDir := "./uploads/weight_exercises/image"
		os.MkdirAll(uploadDir, os.ModePerm)

		extension := filepath.Ext(file.Filename)
		newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
		savePath := filepath.Join(uploadDir, newFileName)

		if err := c.SaveUploadedFile(file, savePath); err == nil {
			if exercise.WetImage != "" {
				os.Remove("./" + exercise.WetImage)
			}
			exercise.WetImage = "uploads/weight_exercises/image/" + newFileName
		}
	}

	// Loop video upload
	loopVideoFile, loopVideoErr := c.FormFile("wet_loop_video")
	if loopVideoErr == nil {
		if verr := helpers.ValidateVideoUpload(loopVideoFile); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		loopDir := "./uploads/weight_exercises/videoloop"
		os.MkdirAll(loopDir, os.ModePerm)
		loopExt := filepath.Ext(loopVideoFile.Filename)
		loopName := fmt.Sprintf("%d_loop%s", time.Now().UnixNano(), loopExt)
		loopPath := filepath.Join(loopDir, loopName)
		if err := c.SaveUploadedFile(loopVideoFile, loopPath); err == nil {
			if exercise.WetLoopVideo != "" {
				os.Remove("./" + exercise.WetLoopVideo)
			}
			exercise.WetLoopVideo = "uploads/weight_exercises/videoloop/" + loopName
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

	var exercise models.WeightExercise
	if err := config.DB.First(&exercise, id).Error; err == nil {
		if exercise.WetImage != "" {
			os.Remove("./" + exercise.WetImage)
		}
		if exercise.WetLoopVideo != "" {
			os.Remove("./" + exercise.WetLoopVideo)
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
		log.Printf("GetExerciseMuscleDetails: query failed: %v", err)
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

	// 2. รับและบันทึกไฟล์รูปภาพ
	imagePath := ""
	file, err := c.FormFile("cdo_image")
	if err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		uploadDir := "./uploads/cardio/images"
		os.MkdirAll(uploadDir, os.ModePerm)

		extension := filepath.Ext(file.Filename)
		newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
		savePath := filepath.Join(uploadDir, newFileName)

		if err := c.SaveUploadedFile(file, savePath); err == nil {
			imagePath = "uploads/cardio/images/" + newFileName
		}
	}

	// Loop video upload
	loopVideoPath := ""
	loopFile, loopErr := c.FormFile("cdo_loop_video")
	if loopErr == nil {
		if verr := helpers.ValidateVideoUpload(loopFile); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		loopDir := "./uploads/cardio/videoloop"
		os.MkdirAll(loopDir, os.ModePerm)
		loopExt := filepath.Ext(loopFile.Filename)
		loopName := fmt.Sprintf("%d_loop%s", time.Now().UnixNano(), loopExt)
		loopPath := filepath.Join(loopDir, loopName)
		if err := c.SaveUploadedFile(loopFile, loopPath); err == nil {
			loopVideoPath = "uploads/cardio/videoloop/" + loopName
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
		CdoHasDistance: int8(cdoHasDistance),
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
	file, err := c.FormFile("cdo_image")
	if err == nil {
		if verr := helpers.ValidateImageUpload(file); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		uploadDir := "./uploads/cardio/images"
		os.MkdirAll(uploadDir, os.ModePerm)

		extension := filepath.Ext(file.Filename)
		newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
		savePath := filepath.Join(uploadDir, newFileName)

		if err := c.SaveUploadedFile(file, savePath); err == nil {
			if cardio.CdoImage != "" {
				os.Remove("./" + cardio.CdoImage)
			}
			cardio.CdoImage = "uploads/cardio/images/" + newFileName
		}
	}

	// Loop video upload
	loopFile, loopErr := c.FormFile("cdo_loop_video")
	if loopErr == nil {
		if verr := helpers.ValidateVideoUpload(loopFile); verr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
			return
		}
		loopDir := "./uploads/cardio/videoloop"
		os.MkdirAll(loopDir, os.ModePerm)
		loopExt := filepath.Ext(loopFile.Filename)
		loopName := fmt.Sprintf("%d_loop%s", time.Now().UnixNano(), loopExt)
		loopPath := filepath.Join(loopDir, loopName)
		if err := c.SaveUploadedFile(loopFile, loopPath); err == nil {
			if cardio.CdoLoopVideo != "" {
				os.Remove("./" + cardio.CdoLoopVideo)
			}
			cardio.CdoLoopVideo = "uploads/cardio/videoloop/" + loopName
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
			os.Remove("./" + cardio.CdoImage)
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
	if verr := helpers.ValidateImageUpload(file); verr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": verr.Error()})
		return
	}

	uploadDir := "./uploads/cardio_categories"
	os.MkdirAll(uploadDir, os.ModePerm)
	extension := filepath.Ext(file.Filename)
	newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
	savePath := filepath.Join(uploadDir, newFileName)

	if err := c.SaveUploadedFile(file, savePath); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "อัปโหลดรูปไม่สำเร็จ"})
		return
	}
	if category.CdcImage != "" {
		os.Remove("./" + category.CdcImage)
	}
	category.CdcImage = "uploads/cardio_categories/" + newFileName

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