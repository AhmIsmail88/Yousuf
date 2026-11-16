"""اللمسة الأخيرة على قاعدة المحتوى قبل شحنها — تُشغَّل بعد أي أداة بناء.

    python tools/content_builder/finalize.py [--db assets/db/content.sqlite]

1. فهارس القراءة: صفحة/جزء المصحف، وأذكار القسم (بدلها يمسح كل استعلام
   الجدول كاملاً).
2. VACUUM + ANALYZE: ملف مضغوط وخطط استعلام صحيحة.
3. بصمة المحتوى `content.version` بجانب القاعدة (SHA-256 للملف): التطبيق
   يقارنها بنسخته المحلية فيعرف أن المحتوى تغيّر — حتى لو بقي الحجم نفسه
   (حجم SQLite مضاعف لـ ٤٠٩٦ فلا يصلح معياراً).
"""

from __future__ import annotations

import argparse
import hashlib
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.sqlite"

INDEXES = [
    "CREATE INDEX IF NOT EXISTS idx_ayah_page ON ayah(page, surah_id, number)",
    "CREATE INDEX IF NOT EXISTS idx_ayah_juz ON ayah(juz)",
    "CREATE INDEX IF NOT EXISTS idx_dhikr_category ON dhikr(category_id, id)",
    "CREATE INDEX IF NOT EXISTS idx_hadith_book ON hadith(book_id, number)",
]


def finalize(db_path: Path) -> str:
    db = sqlite3.connect(db_path)
    try:
        for statement in INDEXES:
            db.execute(statement)
        db.commit()
        db.execute("ANALYZE")
        db.commit()
        db.execute("VACUUM")
    finally:
        db.close()

    digest = hashlib.sha256(db_path.read_bytes()).hexdigest()
    stamp = db_path.with_name("content.version")
    stamp.write_text(digest, encoding="utf-8")
    return digest


def main() -> int:
    parser = argparse.ArgumentParser(description="فهارس + بصمة قاعدة المحتوى")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()
    if not args.db.exists():
        print(f"لا توجد قاعدة: {args.db}", file=sys.stderr)
        return 1
    digest = finalize(args.db)
    print(f"تم: {args.db.name} · البصمة {digest[:16]}…")
    return 0


if __name__ == "__main__":
    sys.exit(main())
