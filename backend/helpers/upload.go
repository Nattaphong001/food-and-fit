package helpers

import (
	"errors"
	"mime/multipart"
	"net/http"
	"regexp"
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
