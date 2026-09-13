# Food & Fit — Admin Web

แอปฝั่งแอดมิน (Flutter Web) ของโปรเจกต์ Food & Fit — ภาพรวมระบบ, screenshot, สถาปัตยกรรม ดูที่
[README หลัก](../README.md)

## รัน

```
flutter pub get
flutter run -d chrome --web-port=8090
```

ต้องมี backend รันอยู่ที่ `http://localhost:8081/api` ก่อน และ port `8090` ต้องตรงกับ
`ALLOWED_ORIGINS` ใน `backend/.env`

## กติกาพัฒนา

ดู [CLAUDE.md](CLAUDE.md) (workspace นี้) และ [../CLAUDE.md](../CLAUDE.md) (สูตรคำนวณ/DB
convention ที่ใช้ร่วมกันทุก workspace)
