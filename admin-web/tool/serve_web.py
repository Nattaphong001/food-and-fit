"""
เสิร์ฟ build/web แบบ multi-thread (แก้ปัญหา python -m http.server เป็น
single-thread แล้วหลุด 404 ตอน TestSprite รัน test ขนานกัน)

ใช้แทน: python -m http.server 8090 --directory build/web

รัน:
    python tool/serve_web.py [PORT]

PORT default = 8090 (ต้องตรงกับ ALLOWED_ORIGINS ใน food_and_fit_api/.env)
"""

import sys
from functools import partial
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

DEFAULT_PORT = 8090
WEB_DIR = Path(__file__).resolve().parent.parent / "build" / "web"


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT

    if not WEB_DIR.is_dir():
        print(f"ไม่พบ {WEB_DIR} — รัน `flutter build web --release` ก่อน")
        sys.exit(1)

    handler = partial(SimpleHTTPRequestHandler, directory=str(WEB_DIR))
    server = ThreadingHTTPServer(("127.0.0.1", port), handler)
    print(f"serving {WEB_DIR} at http://127.0.0.1:{port} (threaded)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
