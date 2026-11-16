#!/usr/bin/env python3
"""يستورد «الأربعون النووية» إلى content.sqlite.

المصدر: fawazahmed0/hadith-api — ترخيص Unlicense (ملكية عامة)،
النسخة العربية ``ara-nawawi`` (٤٢ حديثاً).

كل نص منقول حرفياً. ``reviewed_by`` يبقى NULL حتى توقيع المراجع (SPEC §4).

الاستخدام (من مجلد yousuf/):
    python tools/content_builder/hadith.py
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = PROJECT_ROOT / "assets" / "db" / "content.sqlite"
RAW_DIR = Path(__file__).resolve().parent / "out" / "raw" / "hadith"

API_URL = "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions/ara-nawawi.json"
BOOK_SLUG = "nawawi40"
BOOK_NAME = "الأربعون النووية"


def fetch(url: str, filename: str) -> dict:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    path = RAW_DIR / filename
    if not path.exists():
        print("تنزيل:", url)
        request = urllib.request.Request(url, headers={"User-Agent": "YousufBuilder/0.2"})
        with urllib.request.urlopen(request, timeout=120) as response:
            path.write_bytes(response.read())
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> int:
    parser = argparse.ArgumentParser(description="استيراد الأربعين النووية")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.db.exists():
        print("فشل: قاعدة المحتوى غير موجودة")
        return 1

    payload = fetch(API_URL, "ara-nawawi.json")
    hadiths = payload.get("hadiths") or []
    if len(hadiths) != 42:
        print(f"تحذير: العدد {len(hadiths)} بدل 42")

    db = sqlite3.connect(args.db)
    db.execute(
        "INSERT INTO hadith_book (slug, name_ar, total) VALUES (?, ?, ?)"
        " ON CONFLICT(slug) DO UPDATE SET name_ar = excluded.name_ar,"
        " total = excluded.total",
        (BOOK_SLUG, BOOK_NAME, len(hadiths)),
    )
    book_id = db.execute(
        "SELECT id FROM hadith_book WHERE slug = ?", (BOOK_SLUG,)
    ).fetchone()[0]
    db.execute("DELETE FROM hadith WHERE book_id = ?", (book_id,))

    inserted = 0
    for item in hadiths:
        text = (item.get("text") or "").strip()
        if not text:
            continue
        number = int(item.get("hadithnumber") or 0)
        db.execute(
            "INSERT INTO hadith (book_id, number, chapter, text_ar, narrator,"
            " grade, grader, topic_tags) VALUES (?, ?, NULL, ?, NULL, NULL, NULL, NULL)",
            (book_id, number, text),
        )
        inserted += 1

    if args.dry_run:
        db.rollback()
        print(f"تجربة: {inserted} حديثاً — لم تُحفظ.")
        return 0

    db.execute(
        "UPDATE content_version SET version = ?", ("0.3.0-hadith",)
    )
    db.commit()
    total = db.execute("SELECT COUNT(*) FROM hadith").fetchone()[0]
    db.close()
    print(f"حُفظ {inserted} حديثاً في «{BOOK_NAME}» · إجمالي الحديث: {total}")
    print("reviewed_by = NULL (قيد المراجعة الشرعية).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
