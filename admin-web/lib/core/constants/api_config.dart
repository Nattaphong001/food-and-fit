// ตั้งค่า Base URL ของ API แยกจากโค้ด — override ตอนรัน/build ด้วย
// --dart-define=API_BASE_URL=https://your-domain.example
// ค่า default คือ backend dev บนเครื่อง (ต้องตั้ง ALLOWED_ORIGINS ใน .env ฝั่ง Go
// ให้ตรงกับ origin ของเว็บ admin ตอน dev ด้วย — ดู README)
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8081',
  );
}
