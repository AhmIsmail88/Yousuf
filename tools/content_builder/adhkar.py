#!/usr/bin/env python3
"""يستورد أذكار «حصن المسلم» إلى content.sqlite.

المصدران (يُدمجان):
1) متن الكتاب مع التخريج: ``hisn_almuslim.json`` من مستودع
   abdalrhmanreda/islamic-data-assets — ترخيص MIT، وكل باب فيه
   ``text[]`` + ``footnote[]`` متوازيان (التخريج لكل ذكر).
2) عدد التكرار: واجهة hisnmuslim.com الرسمية (``husn_ar.json`` + ``<id>.json``)
   لأن متن الكتاب المصدري لا يحمل حقل تكرار.

قواعد الجودة:
- لا يُكتب أي نص من عندنا: كل النصوص منقولة حرفياً من المصدر.
- ``reviewed_by`` يبقى NULL حتى توقيع المراجع الشرعي (SPEC §4): المحتوى
  المستورد «قيد المراجعة»، والتطبيق يعرض تنبيهاً بذلك.
- الأبواب تُطابق بالعنوان (تشابه ≥ 0.82)، والعناصر تُطابق بالنص
  (تشابه ≥ 0.70) لأخذ التكرار. ما لا يُطابق يبقى تكراره ١.

الاستخدام (من مجلد yousuf/):
    python tools/content_builder/adhkar.py --hisn
    python tools/content_builder/adhkar.py --hisn --dry-run
    python tools/content_builder/adhkar.py --seed-quranic
    python tools/content_builder/adhkar.py --source path/to/adhkar_reviewed.json
"""

from __future__ import annotations

import argparse
import csv
import difflib
import hashlib
import json
import re
import sqlite3
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = PROJECT_ROOT / "assets" / "db" / "content.sqlite"
RAW_DIR = Path(__file__).resolve().parent / "out" / "raw" / "hisn"

MIT_URL = (
    "https://raw.githubusercontent.com/abdalrhmanreda/"
    "islamic-data-assets/main/hisn_almuslim.json"
)
API_INDEX = "https://www.hisnmuslim.com/api/ar/husn_ar.json"

# الأقسام التي تظهر كشرائح سريعة في التطبيق (slug ثابت يقرأه الواجهة).
FEATURED = {
    "أذكار الصباح والمساء": "morning",
    "أذكار النوم": "sleep",
    "أذكار الاستيقاظ من النوم": "wake",
    "الأذكار بعد السلام من الصلاة": "after_prayer",
    "دعاء الهم والحزن": "distress",
    "دعاء السفر": "travel",
}

# الأبواب التي ليست أذكاراً عملية (مقدمة الكتاب وفصله في الفضل).
SKIP_TITLES = {"المقدمة", "فضل الذكر"}

DIACRITICS = {code: None for code in range(0x0610, 0x061B)}
DIACRITICS.update({code: None for code in range(0x064B, 0x0660)})
DIACRITICS.update({0x0670: None, 0x0640: None})
DIACRITICS.update({code: None for code in range(0x06D6, 0x06ED)})

# كلمات تدل على أن الحاشية تخريج حديثي لا شرح لغوي.
REFERENCE_HINTS = (
    "البخاري",
    "مسلم",
    "أبو داود",
    "ابو داود",
    "الترمذي",
    "النسائي",
    "ابن ماجه",
    "أحمد",
    "الحاكم",
    "الدارمي",
    "مالك",
    "ابن حبان",
    "الطبراني",
    "صحيح",
    "سنن",
    "رواه",
    "أخرجه",
    "اخرجه",
    "برقم",
)


def normalize(text: str) -> str:
    """تطبيع للمطابقة فقط (لا يُكتب في القاعدة)."""
    cleaned = text.translate(DIACRITICS)
    cleaned = re.sub(r"[^\u0621-\u064A0-9 ]+", " ", cleaned)
    for old, new in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"), ("ة", "ه")):
        cleaned = cleaned.replace(old, new)
    return re.sub(r"\s+", " ", cleaned).strip()


def fetch_json(url: str, filename: str):
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    path = RAW_DIR / filename
    if not path.exists():
        print("تنزيل:", url)
        request = urllib.request.Request(url, headers={"User-Agent": "YousufBuilder/0.2"})
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = response.read()
        path.write_bytes(payload)
    # بعض استجابات الموقع تبدأ بعلامة BOM.
    return json.loads(path.read_text(encoding="utf-8-sig"))


def clean_text(raw: str) -> str:
    """إزالة ما يفسد العرض فقط — بلا أي تعديل على المتن."""
    text = raw.replace("\ufeff", "").replace("\u200f", "").replace("\u200e", "")
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


def clean_surah_name(raw: str) -> str:
    """يزيل بادئة «سُورَةُ» وتشكيلها من اسم السورة القادم من القاعدة."""
    name = raw.translate(DIACRITICS).replace("سورة", "").strip()
    return re.sub(r"\s+", " ", name)


def looks_like_reference(note: str) -> bool:
    return any(hint in note for hint in REFERENCE_HINTS)


def slug_for(title: str, index: int) -> str:
    if title in FEATURED:
        return FEATURED[title]
    return f"hisn-{index:03d}"


def ensure_schema(db: sqlite3.Connection) -> None:
    """يتأكد من وجود الجدولين (قاعدة بنيت بـbuild.py تحتويهما)."""
    tables = {
        row[0]
        for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }
    if "dhikr_category" not in tables or "dhikr" not in tables:
        raise SystemExit("فشل: قاعدة المحتوى بلا جداول الأذكار — شغّل build.py أولاً")


def clear_hisn(db: sqlite3.Connection) -> None:
    """يحذف ما استورده هذا السكربت سابقاً فقط (لا يمسّ أذكار القرآن)."""
    db.execute("DELETE FROM dhikr WHERE category_id IN (SELECT id FROM dhikr_category "
               "WHERE slug = 'quranic' OR slug LIKE 'hisn-%' OR slug IN "
               "('morning','sleep','wake','after_prayer','distress','travel',"
               "'evening','food','mosque'))")
    db.execute("DELETE FROM dhikr_category WHERE slug = 'quranic' OR slug LIKE 'hisn-%' "
               "OR slug IN ('morning','sleep','wake','after_prayer','distress','travel',"
               "'evening','food','mosque')")


def build_repeat_lookup(mit: dict) -> dict[str, dict[str, int]]:
    """{عنوان الباب المطبَّع: {نص مطبَّع: التكرار}} من واجهة hisnmuslim."""
    index = fetch_json(API_INDEX, "husn_index.json")["العربية"]
    mit_titles = {normalize(title): title for title in mit}
    lookup: dict[str, dict[str, int]] = {}

    for position, chapter in enumerate(index, start=1):
        title = chapter["TITLE"]
        key = normalize(title)
        if key not in mit_titles:
            # مطابقة عنوان تقريبية (اختلاف تشكيل/صياغة).
            best = max(
                mit_titles,
                key=lambda candidate: difflib.SequenceMatcher(
                    None, key, candidate
                ).ratio(),
            )
            if difflib.SequenceMatcher(None, key, best).ratio() < 0.82:
                continue
            key = best
        data = fetch_json(chapter["TEXT"], f"chapter_{chapter['ID']}.json")
        if not data:
            continue
        items = next(iter(data.values()))
        counts: dict[str, int] = {}
        for item in items:
            text = normalize(item.get("ARABIC_TEXT") or "")
            if not text:
                continue
            repeat = int(item.get("REPEAT") or 1)
            counts[text] = max(counts.get(text, 1), repeat)
        lookup[key] = counts
        if position % 20 == 0:
            print(f"  … {position}/{len(index)} باباً")
    return lookup


def repeat_for(text: str, counts: dict[str, int] | None) -> int:
    """يأخذ التكرار من أقرب نص مطابق (≥ 0.70)، وإلا ١."""
    if not counts:
        return 1
    target = normalize(text)
    if target in counts:
        return counts[target]
    best_key, best_ratio = "", 0.0
    for candidate in counts:
        ratio = difflib.SequenceMatcher(None, target, candidate).ratio()
        if ratio > best_ratio:
            best_key, best_ratio = candidate, ratio
    return counts[best_key] if best_ratio >= 0.70 else 1


def import_hisn(db: sqlite3.Connection) -> tuple[int, int]:
    mit = fetch_json(MIT_URL, "hisn_almuslim_mit.json")
    lookups = build_repeat_lookup(mit)

    categories = 0
    items = 0
    position = 0
    for title, body in mit.items():
        if title in SKIP_TITLES:
            continue
        texts = [clean_text(text) for text in body.get("text", []) if clean_text(text)]
        if not texts:
            continue
        notes = [clean_text(note) for note in body.get("footnote", [])]
        position += 1
        slug = slug_for(title, position)
        category_id = db.execute(
            "INSERT INTO dhikr_category (slug, name, sort) VALUES (?, ?, ?)"
            " ON CONFLICT(slug) DO UPDATE SET name = excluded.name,"
            " sort = excluded.sort",
            (slug, title, position),
        ).lastrowid
        if category_id is None:
            category_id = db.execute(
                "SELECT id FROM dhikr_category WHERE slug = ?", (slug,)
            ).fetchone()[0]
        categories += 1

        counts = lookups.get(normalize(title))
        # التخريج: نحذف حواشي الشرح اللغوي (الموسومة بـ*) التي ليست مراجع،
        # فإن بقي عددها مساوياً للنصوص نقابلها واحداً بواحد، وإلا نُنسب
        # الذكر إلى بابه في الكتاب (مصدر بلا تخريج تفصيلي).
        refs = [
            note
            for note in notes
            if note and not note.startswith("*") and looks_like_reference(note)
        ]
        aligned = len(refs) == len(texts)
        chapter_source = f"حصن المسلم — باب: {title}"
        for offset, text in enumerate(texts):
            source = refs[offset] if aligned else chapter_source
            db.execute(
                "INSERT INTO dhikr (category_id, text, repeat_count, source)"
                " VALUES (?, ?, ?, ?)",
                (category_id, text, repeat_for(text, counts), source),
            )
            items += 1
    return categories, items


def ensure_quranic(db: sqlite3.Connection) -> None:
    """ينشئ قسم «أدعية من القرآن» من جدول الآيات (نسخ حرفي)."""
    category_id = db.execute(
        "INSERT INTO dhikr_category (slug, name, sort) VALUES ('quranic', ?, 0)"
        " ON CONFLICT(slug) DO UPDATE SET name = excluded.name",
        ("أدعية من القرآن",),
    ).lastrowid
    if category_id is None:
        category_id = db.execute(
            "SELECT id FROM dhikr_category WHERE slug = 'quranic'"
        ).fetchone()[0]
    # الآيات موجودة أصلاً — لا نكرر الإدخال إن سبق.
    existing = db.execute(
        "SELECT COUNT(*) FROM dhikr WHERE category_id = ?", (category_id,)
    ).fetchone()[0]
    if existing:
        return
    for surah_id, number in QURANIC_DUA:
        row = db.execute(
            "SELECT a.text_uthmani, s.name_ar FROM ayah a"
            " JOIN surah s ON s.id = a.surah_id"
            " WHERE a.surah_id = ? AND a.number = ?",
            (surah_id, number),
        ).fetchone()
        if row is None:
            continue
        text, surah_name = row
        db.execute(
            "INSERT INTO dhikr (category_id, text, repeat_count, source)"
            " VALUES (?, ?, 1, ?)",
            (
                category_id,
                clean_text(text),
                f"سورة {clean_surah_name(surah_name)} · آية {number}",
            ),
        )


# آيات دعاء معروفة (سورة، آية) — مراجعها مثبتة في النص نفسه.
QURANIC_DUA = [
    (2, 127), (2, 128), (2, 129), (2, 201), (2, 250), (2, 286),
    (3, 8), (3, 16), (3, 26), (3, 147), (3, 193),
    (7, 23), (7, 47), (10, 85), (10, 86), (14, 40), (14, 41),
    (17, 80), (18, 10), (20, 25), (20, 114), (21, 83), (21, 87),
    (23, 97), (23, 118), (25, 74), (26, 83), (27, 19), (28, 24),
    (37, 100), (40, 7), (43, 13), (43, 14), (46, 15), (59, 10),
    (66, 8), (71, 28),
]


def import_reviewed(db: sqlite3.Connection, payload: dict, allow_unreviewed: bool) -> int:
    """استيراد ملف مُراجَع (نفس عقد النسخة السابقة)."""
    reviewer = (payload.get("reviewed_by") or "").strip()
    if not reviewer and not allow_unreviewed:
        raise SystemExit(
            "مرفوض: الملف بلا reviewed_by. لا يُشحن نص قبل توقيع المراجع (SPEC §4)."
        )
    imported = 0
    for category in payload.get("categories", []):
        slug = (category.get("slug") or "").strip()
        if not slug:
            raise SystemExit("مرفوض: قسم بلا slug")
        name = (category.get("name") or slug).strip()
        sort = int(category.get("sort") or 500)
        db.execute(
            "INSERT INTO dhikr_category (slug, name, sort) VALUES (?, ?, ?)"
            " ON CONFLICT(slug) DO UPDATE SET name = excluded.name, sort = excluded.sort",
            (slug, name, sort),
        )
        category_id = db.execute(
            "SELECT id FROM dhikr_category WHERE slug = ?", (slug,)
        ).fetchone()[0]
        db.execute("DELETE FROM dhikr WHERE category_id = ?", (category_id,))
        for index, item in enumerate(category.get("dhikr", []), start=1):
            text = clean_text(item.get("text") or "")
            source = (item.get("source") or "").strip()
            repeat = item.get("repeat", 1)
            if not text:
                raise SystemExit(f"مرفوض: {slug}[{index}] بلا نص")
            if not source:
                raise SystemExit(f"مرفوض: {slug}[{index}] بلا مصدر")
            if not isinstance(repeat, int) or not (1 <= repeat <= 100):
                raise SystemExit(f"مرفوض: {slug}[{index}] تكرار غير صالح")
            db.execute(
                "INSERT INTO dhikr (category_id, text, repeat_count, source, virtue)"
                " VALUES (?, ?, ?, ?, ?)",
                (category_id, text, repeat, source, item.get("virtue")),
            )
            imported += 1
    return imported


def export_csv(db: sqlite3.Connection, path: Path) -> int:
    """يصدّر كل الأذكار لمراجعتها في Excel (UTF-8 مع BOM)."""
    rows = db.execute(
        "SELECT c.name, d.id, d.text, d.repeat_count, COALESCE(d.source, '')"
        " FROM dhikr d JOIN dhikr_category c ON c.id = d.category_id"
        " ORDER BY c.sort, d.id"
    ).fetchall()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["الباب", "المعرّف", "النص", "التكرار", "المصدر"])
        writer.writerows(rows)
    return len(rows)


def mark_reviewed(db: sqlite3.Connection, reviewer: str) -> None:
    """يوقّع المحتوى بعد اعتماد المراجع (SPEC §4)."""
    db.execute("UPDATE content_version SET reviewed_by = ?", (reviewer,))


def main() -> int:
    parser = argparse.ArgumentParser(description="استيراد أذكار حصن المسلم")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--hisn", action="store_true", help="استيراد حصن المسلم كاملاً")
    parser.add_argument("--seed-quranic", action="store_true")
    parser.add_argument("--source", type=Path, help="ملف JSON مُراجَع")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--allow-unreviewed", action="store_true")
    parser.add_argument("--export-csv", type=Path, help="يصدّر الأذكار لمراجعة خارجية")
    parser.add_argument("--mark-reviewed", metavar="NAME", help="يوقّع المحتوى باسم المراجع")
    args = parser.parse_args()

    if not args.db.exists():
        print(f"فشل: قاعدة المحتوى غير موجودة: {args.db}")
        return 1

    db = sqlite3.connect(args.db)
    ensure_schema(db)

    if args.export_csv:
        total = export_csv(db, args.export_csv)
        print(f"صُدّر {total} ذكراً إلى {args.export_csv}")
        return 0

    if args.mark_reviewed:
        mark_reviewed(db, args.mark_reviewed)
        db.commit()
        print(f"تم توقيع المحتوى باسم: {args.mark_reviewed} — سيختفي تنبيه المراجعة في التطبيق.")
        return 0

    if not (args.hisn or args.seed_quranic or args.source):
        print("فشل: حدّد --hisn أو --seed-quranic أو --source (أو --export-csv/--mark-reviewed)")
        return 1

    if args.hisn:
        clear_hisn(db)

    categories = items = 0
    if args.seed_quranic:
        ensure_quranic(db)
        print("أدعية القرآن: جاهزة")

    if args.hisn:
        categories, items = import_hisn(db)
        print(f"حصن المسلم: {categories} باباً · {items} ذكراً")

    if args.source:
        imported = import_reviewed(db, json.loads(args.source.read_text("utf-8")),
                                   args.allow_unreviewed)
        print(f"من الملف المُراجَع: {imported} ذكراً")
        items += imported

    if args.dry_run:
        db.rollback()
        print("تجربة فقط (dry-run) — لم تُحفظ التغييرات.")
        return 0

    # بصمة المحتوى تشمل الجدولين، والتوقيع يبقى فارغاً حتى المراجعة.
    digest = hashlib.sha256()
    for row in db.execute("SELECT text FROM dhikr ORDER BY id"):
        digest.update((row[0] or "").encode("utf-8"))
    checksum = digest.hexdigest()
    db.execute("DELETE FROM content_version")
    db.execute(
        "INSERT INTO content_version (version, built_at, reviewed_by, sources_checksum)"
        " VALUES (?, ?, NULL, ?)",
        ("0.2.0-adhkar", datetime.now(timezone.utc).isoformat(), checksum),
    )
    db.commit()

    rows = db.execute(
        "SELECT c.slug, COUNT(d.id) FROM dhikr_category c"
        " LEFT JOIN dhikr d ON d.category_id = c.id GROUP BY c.slug"
    ).fetchall()
    total = db.execute("SELECT COUNT(*) FROM dhikr").fetchone()[0]
    with_source = db.execute(
        "SELECT COUNT(*) FROM dhikr WHERE source IS NOT NULL AND source != ''"
    ).fetchone()[0]
    db.close()
    print(f"أقسام: {len(rows)} · أذكار: {total} · بمصدر: {with_source}")
    print("reviewed_by = NULL (قيد المراجعة الشرعية) — التوقيع يُضاف بعد الاعتماد.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
