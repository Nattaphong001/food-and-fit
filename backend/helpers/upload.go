package helpers

import (
	"errors"
	"fmt"
	"log/slog"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"time"

	"github.com/gin-gonic/gin"
)

const (
	MaxImageUploadBytes = 5 * 1024 * 1024  // 5 MB
	MaxVideoUploadBytes = 50 * 1024 * 1024 // 50 MB
)

var allowedImageTypes = map[string]bool{
	"image/jpeg": true,
	"image/png":  true,
	"image/webp": true,
}

var allowedVideoTypes = map[string]bool{
	"video/mp4": true,
}

// detectContentType อ่าน 512 byte แรกของไฟล์เพื่อตรวจชนิดไฟล์จริง ไม่ใช่ดูจากนามสกุลที่ผู้ใช้ตั้ง
func detectContentType(fh *multipart.FileHeader) (string, error) {
	f, err := fh.Open()
	if err != nil {
		return "", err
	}
	defer f.Close()

	buf := make([]byte, 512)
	n, err := f.Read(buf)
	if err != nil && n == 0 {
		return "", err
	}
	return http.DetectContentType(buf[:n]), nil
}

// ValidateImageUpload ตรวจขนาดไฟล์และ MIME type จริงของรูปภาพที่อัปโหลด (jpeg/png/webp เท่านั้น, ไม่เกิน 5MB)
func ValidateImageUpload(fh *multipart.FileHeader) error {
	if fh.Size > MaxImageUploadBytes {
		return errors.New("ไฟล์รูปภาพมีขนาดใหญ่เกินไป (สูงสุด 5MB)")
	}
	contentType, err := detectContentType(fh)
	if err != nil {
		return errors.New("ไม่สามารถอ่านไฟล์ที่อัปโหลดได้")
	}
	if !allowedImageTypes[contentType] {
		return errors.New("รองรับเฉพาะไฟล์รูปภาพชนิด JPEG, PNG หรือ WEBP เท่านั้น")
	}
	return nil
}

// ValidateVideoUpload ตรวจขนาดไฟล์และ MIME type จริงของวิดีโอที่อัปโหลด (mp4 เท่านั้น, ไม่เกิน 50MB)
func ValidateVideoUpload(fh *multipart.FileHeader) error {
	if fh.Size > MaxVideoUploadBytes {
		return errors.New("ไฟล์วิดีโอมีขนาดใหญ่เกินไป (สูงสุด 50MB)")
	}
	contentType, err := detectContentType(fh)
	if err != nil {
		return errors.New("ไม่สามารถอ่านไฟล์ที่อัปโหลดได้")
	}
	if !allowedVideoTypes[contentType] {
		return errors.New("รองรับเฉพาะไฟล์วิดีโอชนิด MP4 เท่านั้น")
	}
	return nil
}

// SaveUploadedImage - validate (ValidateImageUpload) แล้วบันทึกไฟล์รูปจาก field ที่ระบุ ตั้งชื่อไฟล์
// กันซ้ำด้วย timestamp อัตโนมัติ คืน path สัมพัทธ์ (public, เช่น "uploads/weight_exercises/image/...")
// สำหรับเก็บ DB — เดิมโค้ดนี้อินไลน์ซ้ำ 6+ จุดใน exercise_controller.go รวมมาไว้จุดเดียว
// ถ้า validate ไม่ผ่านคืน error (caller ตอบ 400) ถ้า validate ผ่านแต่บันทึกไฟล์จริงลงดิสก์ล้มเหลว
// คืน "", nil (เงียบๆ ไม่ error — พฤติกรรมเดิมทุกจุดที่เคยอินไลน์สูตรนี้ ยกเว้น
// UpdateCardioCategoryImage ที่ต้องการไฟล์บังคับ จุดนั้นเช็ค newPath=="" เองแล้วตอบ 500 เพิ่ม)
func SaveUploadedImage(c *gin.Context, file *multipart.FileHeader, uploadDir, publicDir string) (string, error) {
	if verr := ValidateImageUpload(file); verr != nil {
		return "", verr
	}
	if err := os.MkdirAll(uploadDir, 0750); err != nil {
		return "", err
	}
	extension := filepath.Ext(file.Filename)
	newFileName := fmt.Sprintf("%d%s", time.Now().UnixNano(), extension)
	savePath := filepath.Join(uploadDir, newFileName)
	if err := c.SaveUploadedFile(file, savePath); err != nil {
		return "", nil
	}
	return publicDir + "/" + newFileName, nil
}

// SaveUploadedVideo - เหมือน SaveUploadedImage แต่ validate ด้วย ValidateVideoUpload และตั้งชื่อไฟล์
// รูปแบบ "<timestamp>_loop<ext>" — ใช้เฉพาะ loop video ของท่าฝึก/คาร์ดิโอเท่านั้น (วิดีโอสอนเต็มใช้ลิงก์
// YouTube ผ่าน ValidateTutorialVideoURL แยกต่างหาก ไม่ใช่ไฟล์อัปโหลด)
func SaveUploadedVideo(c *gin.Context, file *multipart.FileHeader, uploadDir, publicDir string) (string, error) {
	if verr := ValidateVideoUpload(file); verr != nil {
		return "", verr
	}
	if err := os.MkdirAll(uploadDir, 0750); err != nil {
		return "", err
	}
	extension := filepath.Ext(file.Filename)
	newFileName := fmt.Sprintf("%d_loop%s", time.Now().UnixNano(), extension)
	savePath := filepath.Join(uploadDir, newFileName)
	if err := c.SaveUploadedFile(file, savePath); err != nil {
		return "", nil
	}
	return publicDir + "/" + newFileName, nil
}

// RemoveOldFile - ลบไฟล์รูป/วิดีโอเก่าตอนแก้ไข/ลบข้อมูล (แทนที่ os.Remove เปล่าๆ ที่เคยเมิน error
// ทิ้งไป 15+ จุด — gosec G104) ไฟล์ไม่มีอยู่แล้วไม่ต้อง log (เคสปกติ เช่นข้อมูลเก่าไม่มีรูป) ส่วน error
// อื่น (permission, disk) log ไว้เป็น warning เพื่อให้ orphan file ที่ลบไม่ได้จริงถูกสังเกตเห็น ไม่ error
// กลับไปหา caller เพราะพฤติกรรมเดิมตั้งใจให้ลบรูปเก่าล้มเหลวไม่บล็อกการบันทึกข้อมูลใหม่
func RemoveOldFile(path string) {
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		slog.Warn("could not remove old upload file", "path", path, "err", err)
	}
}

var youtubeURLPattern = regexp.MustCompile(`^https://(www\.)?(youtube\.com/watch\?v=|youtu\.be/|youtube\.com/shorts/)`)

// ValidateTutorialVideoURL ตรวจ wet_video/cdo_video (วิดีโอสอนเต็ม — ลิงก์ YouTube เท่านั้น) ไม่บังคับกรอก
// (ค่าว่างผ่านได้เสมอ) แยกหน้าที่ชัดเจนจาก *_loop_video ที่เป็นไฟล์อัปโหลดในระบบ (ValidateVideoUpload)
func ValidateTutorialVideoURL(url string) error {
	if url == "" {
		return nil
	}
	if !youtubeURLPattern.MatchString(url) {
		return errors.New("ลิงก์วิดีโอสอนต้องเป็น URL ของ YouTube ที่ขึ้นต้นด้วย https://")
	}
	return nil
}
