#!/usr/bin/env python3
"""يفحص content.sqlite المبني: الأعداد، اتساق السور، والـ checksums.

الاستخدام (من مجلد yousuf/):
    python tools/content_builder/verify.py
"""

import hashlib
import json
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "out")
RAW_DIR = os.path.join(OUT_DIR, "raw")
DB_PATH = os.path.join(OUT_DIR, "content.sqlite")
CHECKSUMS_PATH = os.path.join(OUT_DIR, "sources_checksums.json")

REQUIRED_TABLES = [
    "surah", "ayah", "page_line", "word", "ayah_fts", "tafsir", "tafsir_text",
    "hadith_book", "hadith", "dhikr_category", "dhikr", "asma_husna", "event",
    "content_version",
]


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as raw:
        for chunk in iter(lambda: raw.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    if not os.path.exists(DB_PATH):
        print("القاعدة غير موجودة — شغّل build.py أولاً")
        return 1

    failures: list[str] = []
    db = sqlite3.connect(DB_PATH)

    tables = {
        row[0]
        for row in db.execute(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
        )
    }
    for table in REQUIRED_TABLES:
        if table not in tables:
            failures.append(f"جدول مفقود: {table}")

    surah_count = db.execute("SELECT COUNT(*) FROM surah").fetchone()[0]
    ayah_count = db.execute("SELECT COUNT(*) FROM ayah").fetchone()[0]
    if surah_count != 114:
        failures.append(f"عدد السور {surah_count} != 114")
    if ayah_count != 6236:
        failures.append(f"عدد الآيات {ayah_count} != 6236")

    # تطابق عدد الآيات الفعلي مع ayah_count المسجل لكل سورة
    mismatched = db.execute(
        "SELECT s.id, s.ayah_count, COUNT(a.id) FROM surah s"
        " LEFT JOIN ayah a ON a.surah_id = s.id GROUP BY s.id"
        " HAVING s.ayah_count != COUNT(a.id)"
    ).fetchall()
    if mismatched:
        failures.append(f"عدم تطابق ayah_count في {len(mismatched)} سورة")

    # تكامل الحقول الأساسية
    nulls = db.execute(
        "SELECT COUNT(*) FROM ayah WHERE text_uthmani = '' OR text_simple = ''"
        " OR page IS NULL OR juz IS NULL"
    ).fetchone()[0]
    if nulls:
        failures.append(f"{nulls} آية بحقول فارغة/ناقصة")

    version = db.execute(
        "SELECT version, built_at, reviewed_by, sources_checksum FROM content_version"
    ).fetchone()
    if not version:
        failures.append("content_version فارغ")
    elif version[2] is not None:
        print(f"ملاحظة: reviewed_by = {version[2]}")
    else:
        print("المراجعة الشرعية: لم تُسجل بعد (reviewed_by = NULL) — متوقع في هذه المرحلة")

    # checksums للمصادر الخام
    checksums = {}
    for name in ("quran-uthmani.json", "quran-simple.json"):
        path = os.path.join(RAW_DIR, name)
        if not os.path.exists(path):
            failures.append(f"ملف مصدر مفقود: {name}")
            continue
        checksums[name] = sha256_of(path)
    with open(CHECKSUMS_PATH, "w", encoding="utf-8") as out:
        json.dump(checksums, out, indent=2, ensure_ascii=False)

    if version and checksums:
        expected = hashlib.sha256(
            (
                checksums.get("quran-uthmani.json", "")
                + checksums.get("quran-simple.json", "")
            ).encode()
        ).hexdigest()
        if version[3] != expected:
            failures.append("sources_checksum غير مطابق للملفات الخام")

    db.close()

    print(f"سور: {surah_count} · آيات: {ayah_count}")
    print(f"فحص الجداول: {'✓' if not failures else '✗'}")
    if failures:
        for failure in failures:
            print(" -", failure)
        return 1
    print("كل الفحوصات ناجحة ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
