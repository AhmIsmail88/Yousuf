#!/usr/bin/env python3
"""يبني content.sqlite (نص القرآن) من مصادر موثقة الترخيص.

المصادر:
- النص العثماني: alquran.cloud — نسخة quran-uthmani (نص Tanzil، CC BY 3.0)
- النص الإملائي للبحث: alquran.cloud — نسخة quran-simple
  (موقع Tanzil الرسمي قد يتطلب تنزيلاً تفاعلياً؛ alquran.cloud يقدّم نص
   Tanzil نفسه. عند توفر تنزيل Tanzil المباشر يُستبدل المصدر ويُحدَّث checksum.)
- بيانات السور: من نفس الاستجابتين (الاسم، النوع، عدد الآيات).

تنبيه شرعي: النص العثماني يُنسخ حرفياً — يمنع أي تعديل (شرط Tanzil).

الاستخدام (من مجلد yousuf/):
    python tools/content_builder/build.py
"""

import hashlib
import json
import os
import sqlite3
import sys
import urllib.request
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "out")
RAW_DIR = os.path.join(OUT_DIR, "raw")
DB_PATH = os.path.join(OUT_DIR, "content.sqlite")

API_UTHMANI = "https://api.alquran.cloud/v1/quran/quran-uthmani"
API_SIMPLE = "https://api.alquran.cloud/v1/quran/quran-simple"

VERSION = "0.1.0-dev"

# جداول SPEC §5 — تُنشأ جميعها؛ ما لا مصدر له بعد يبقى فارغاً.
SCHEMA = """
CREATE TABLE surah (
    id INTEGER PRIMARY KEY,
    name_ar TEXT NOT NULL,
    name_en TEXT NOT NULL,
    revelation TEXT NOT NULL CHECK (revelation IN ('makki', 'madani')),
    ayah_count INTEGER NOT NULL,
    start_page INTEGER NOT NULL
);
CREATE TABLE ayah (
    id INTEGER PRIMARY KEY,
    surah_id INTEGER NOT NULL REFERENCES surah(id),
    number INTEGER NOT NULL,
    text_uthmani TEXT NOT NULL,
    text_simple TEXT NOT NULL,
    page INTEGER,
    juz INTEGER,
    hizb_quarter INTEGER,
    sajda INTEGER NOT NULL DEFAULT 0,
    UNIQUE (surah_id, number)
);
CREATE TABLE page_line (
    page INTEGER NOT NULL,
    line INTEGER NOT NULL,
    type TEXT NOT NULL,
    first_word_id INTEGER,
    last_word_id INTEGER,
    PRIMARY KEY (page, line)
);
CREATE TABLE word (
    id INTEGER PRIMARY KEY,
    ayah_id INTEGER NOT NULL REFERENCES ayah(id),
    position INTEGER NOT NULL,
    text TEXT NOT NULL,
    root TEXT
);
CREATE VIRTUAL TABLE ayah_fts USING fts5 (
    text_simple,
    ayah_id UNINDEXED
);
CREATE TABLE tafsir (
    id INTEGER PRIMARY KEY,
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    author TEXT,
    bundled INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE tafsir_text (
    tafsir_id INTEGER NOT NULL REFERENCES tafsir(id),
    ayah_id INTEGER NOT NULL REFERENCES ayah(id),
    text TEXT NOT NULL,
    PRIMARY KEY (tafsir_id, ayah_id)
);
CREATE TABLE hadith_book (
    id INTEGER PRIMARY KEY,
    slug TEXT NOT NULL UNIQUE,
    name_ar TEXT NOT NULL,
    total INTEGER
);
CREATE TABLE hadith (
    id INTEGER PRIMARY KEY,
    book_id INTEGER NOT NULL REFERENCES hadith_book(id),
    number INTEGER NOT NULL,
    chapter TEXT,
    text_ar TEXT NOT NULL,
    narrator TEXT,
    grade TEXT,
    grader TEXT,
    topic_tags TEXT
);
CREATE TABLE dhikr_category (
    id INTEGER PRIMARY KEY,
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    sort INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE dhikr (
    id INTEGER PRIMARY KEY,
    category_id INTEGER NOT NULL REFERENCES dhikr_category(id),
    text TEXT NOT NULL,
    repeat_count INTEGER NOT NULL DEFAULT 1,
    source TEXT,
    virtue TEXT,
    audio_ref TEXT
);
CREATE TABLE asma_husna (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    meaning TEXT
);
CREATE TABLE event (
    id INTEGER PRIMARY KEY,
    hijri_month INTEGER NOT NULL,
    hijri_day INTEGER NOT NULL,
    title TEXT NOT NULL,
    kind TEXT NOT NULL,
    note TEXT
);
CREATE TABLE content_version (
    version TEXT NOT NULL,
    built_at TEXT NOT NULL,
    reviewed_by TEXT,
    sources_checksum TEXT NOT NULL
);
"""

DIACRITICS = {code: None for code in range(0x0610, 0x061B)}
DIACRITICS.update({code: None for code in range(0x064B, 0x0660)})
DIACRITICS.update({0x0670: None})
DIACRITICS.update({code: None for code in range(0x06D6, 0x06ED)})


def normalize_arabic(text: str) -> str:
    """تطبيع للبحث فقط: حذف التشكيل وتوحيد الهمزات والألف والياء."""
    cleaned = text.translate(DIACRITICS)
    return (
        cleaned.replace("أ", "ا")
        .replace("إ", "ا")
        .replace("آ", "ا")
        .replace("ى", "ي")
        .replace("ة", "ه")
    )


def fetch(url: str, filename: str) -> str:
    """ينزّل الملف مرة واحدة ويحفظه، ويعيد نصه."""
    os.makedirs(RAW_DIR, exist_ok=True)
    path = os.path.join(RAW_DIR, filename)
    if not os.path.exists(path):
        print("تنزيل:", url)
        request = urllib.request.Request(url, headers={"User-Agent": "YousufBuilder/0.1"})
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = response.read()
        with open(path, "wb") as out:
            out.write(payload)
    with open(path, "rb") as raw:
        return raw.read().decode("utf-8")


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as raw:
        for chunk in iter(lambda: raw.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)

    uthmani = json.loads(fetch(API_UTHMANI, "quran-uthmani.json"))
    simple = json.loads(fetch(API_SIMPLE, "quran-simple.json"))
    if uthmani.get("code") != 200 or simple.get("code") != 200:
        print("فشل التنزيل: استجابة غير ناجحة")
        return 1

    surahs_uthmani = uthmani["data"]["surahs"]
    surahs_simple = simple["data"]["surahs"]

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    db = sqlite3.connect(DB_PATH)
    db.executescript(SCHEMA)

    ayah_id = 0
    total_simple = 0
    for surah_u, surah_s in zip(surahs_uthmani, surahs_simple):
        if surah_u["number"] != surah_s["number"]:
            print("عدم تطابق ترتيب السور")
            return 1
        simple_by_number = {a["numberInSurah"]: a for a in surah_s["ayahs"]}
        ayahs = surah_u["ayahs"]
        start_page = ayahs[0]["page"]
        db.execute(
            "INSERT INTO surah (id, name_ar, name_en, revelation, ayah_count, start_page)"
            " VALUES (?, ?, ?, ?, ?, ?)",
            (
                surah_u["number"],
                surah_u["name"],
                surah_u["englishName"],
                "makki" if surah_u["revelationType"] == "Meccan" else "madani",
                len(ayahs),
                start_page,
            ),
        )
        for ayah in ayahs:
            ayah_id += 1
            simple_ayah = simple_by_number[ayah["numberInSurah"]]
            db.execute(
                "INSERT INTO ayah (id, surah_id, number, text_uthmani, text_simple,"
                " page, juz, hizb_quarter, sajda) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    ayah_id,
                    surah_u["number"],
                    ayah["numberInSurah"],
                    ayah["text"],
                    simple_ayah["text"],
                    ayah.get("page"),
                    ayah.get("juz"),
                    ayah.get("hizbQuarter"),
                    1 if ayah.get("sajda") else 0,
                ),
            )
            db.execute(
                "INSERT INTO ayah_fts (text_simple, ayah_id) VALUES (?, ?)",
                (normalize_arabic(simple_ayah["text"]), ayah_id),
            )
            total_simple += 1

    checksum = hashlib.sha256(
        (sha256_of(os.path.join(RAW_DIR, "quran-uthmani.json"))
         + sha256_of(os.path.join(RAW_DIR, "quran-simple.json"))).encode()
    ).hexdigest()

    db.execute(
        "INSERT INTO content_version (version, built_at, reviewed_by, sources_checksum)"
        " VALUES (?, ?, NULL, ?)",
        (VERSION, datetime.now(timezone.utc).isoformat(), checksum),
    )
    db.commit()

    surah_count = db.execute("SELECT COUNT(*) FROM surah").fetchone()[0]
    ayah_count = db.execute("SELECT COUNT(*) FROM ayah").fetchone()[0]
    fts_count = db.execute("SELECT COUNT(*) FROM ayah_fts").fetchone()[0]
    db.close()

    size = os.path.getsize(DB_PATH)
    print(f"كُتب: {os.path.normpath(DB_PATH)}")
    print(f"سور: {surah_count} · آيات: {ayah_count} · FTS: {fts_count}")
    print(f"الحجم: {size:,} بايت · checksum: {checksum[:16]}…")

    if surah_count != 114 or ayah_count != 6236 or fts_count != 6236:
        print("فشل: الأعداد غير مطابقة (114/6236/6236)")
        return 1
    print("البناء ناجح ✓ — شغّل verify.py للفحص الكامل")
    return 0


if __name__ == "__main__":
    sys.exit(main())
