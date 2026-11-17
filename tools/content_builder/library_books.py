#!/usr/bin/env python3
"""كتب المكتبة (التاريخ والسيرة) — ملف SQLite مضغوط لكل كتاب يُنزَّل عند الطلب.

    python tools/content_builder/library_books.py --out out/library_books

المصادر (حزمة D:/coding/Quran):
- islamic-library.sqlite: البداية والنهاية، تاريخ الطبري، زاد المعاد، لباب النقول،
  سيرة ابن هشام، الكامل في التاريخ — نسخ المكتبة الشاملة. المتون ملك عام.
  حواشي التحقيق الحديث (سيرة ابن هشام) وحواشي الطبعة (البداية والنهاية) تُحذف
  مع علاماتها، ويبقى المتن وحده.
- D:/coding/adhkar/books/adhkar_library.sqlite: كتب الأذكار — الكلم الطيب لابن تيمية،
  الوابل الصيب لابن القيم، الأذكار للنووي (نسخ المكتبة الشاملة). المتون ملك عام،
  وحواشي التحقيق الحديث (الأذكار ت الأرنؤوط) تُحذف ويبقى المتن.
- rahiq-makhtum.sqlite: الرحيق المختوم — بإذن الناشر (دار السلام) لمالك التطبيق.
- D:/كتب عربية: كتب «الإسلام والغرب» — نصوص مستخرجة بـ OCR من نسخ مصوّرة (أو
  نص رقمي لمقالة سوليفان). «الأبطال» لكارليل وترجمة السباعي ملك عام؛ الباقي
  منشور بإذن أصحاب الحقوق لمالك التطبيق (١٧ نوفمبر ٢٠٢٦). يُنقل نص الصفحة
  المصحَّح (`text`) كما هو، والفصل من عمود `part`.
  النص محوَّل من PDF؛ تُصلَح آثار التحويل الآلية فقط (الأقواس المعكوسة، المسافة
  قبل علامات الترقيم) ولا يُمسّ الكلام.

بنية الملف: meta، chapter(id, title, volume, first_page)، page(id, volume,
page_num, chapter_id, text). الضغط قابل للتكرار (mtime=0) فتثبت البصمة.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path

SOURCE_DIR = Path("D:/coding/Quran")
ADHKAR_BOOKS = Path("D:/coding/adhkar/books/adhkar_library.sqlite")

# تبويب المكتبة لكل تصنيف — كتاب جديد بتصنيف جديد يحتاج سطراً هنا.
SECTIONS = {
    "سيرة": "السيرة والتاريخ",
    "سيرة وهدي": "السيرة والتاريخ",
    "تاريخ": "السيرة والتاريخ",
    "علوم القرآن": "علوم القرآن",
    "أذكار": "الأذكار",
    "متون": "المتون",
    "الإسلام والغرب": "الإسلام والغرب",
}

WEST_DIR = Path("D:/كتب عربية")

# كتب «الإسلام والغرب»: (المعرّف، المجلد/الملف، المؤلف كما يُعرض، الحقوق)
WEST = [
    ("why_they_hate_him", "لماذا يكرهونه/لماذا_يكرهونه.sqlite",
     "د. باسم خفاجي", "بإذن صاحب الحق لمالك التطبيق"),
    ("orientalism_said", "الاستشراق/الاستشراق.sqlite",
     "إدوارد سعيد · ترجمة محمد عناني", "بإذن صاحب الحق لمالك التطبيق"),
    ("heroes_carlyle", "الأبطال وعبادة البطولة/الأبطال وعبادة البطولة.sqlite",
     "توماس كارليل · ترجمة محمد السباعي", "ملك عام (ت ١٨٨١م، والمترجم ت ١٩٣١م)"),
    ("islam_christianity", "الإسلام والمسيحية/الإسلام والمسيحية.sqlite",
     "أليكسي جورافيسكي", "بإذن صاحب الحق لمالك التطبيق"),
    ("europe_islam_djait", "أوروبا والإسلام/أوروبا والإسلام.sqlite",
     "هشام جعيط", "بإذن صاحب الحق لمالك التطبيق"),
    ("islam_influence_europe", "تأثير الإسلام في أوروبا/تأثير الإسلام في أوروبا.sqlite",
     "وليام مونتغمري واط · ترجمة سارة الذيب", "بإذن صاحب الحق لمالك التطبيق"),
    ("west_muslim_world", "الغرب والعالم الإسلامي/الغرب والعالم الإسلامي.sqlite",
     "أنطوني ت. سوليفان · ترجمة مروان حمدان", "بإذن صاحب الحق لمالك التطبيق"),
]

# كتب الأذكار: (المعرّف، المعرّف في المصدر، الاسم، المؤلف، حذف الحواشي)
ADHKAR = [
    ("adhkar_nawawi", "adhkar_nawawi", "الأذكار", "الإمام النووي (ت ٦٧٦هـ)", "parens"),
    ("kalim_tayyib", "kalm_tayyib", "الكلم الطيب", "ابن تيمية (ت ٧٢٨هـ)", None),
    ("wabil_sayyib", "wabil_sayyib", "الوابل الصيب من الكلم الطيب",
     "ابن قيم الجوزية (ت ٧٥١هـ)", None),
]
FORMAT_VERSION = 1

# (المعرّف في التطبيق، المعرّف في المصدر، الاسم، المؤلف، الوصف المختصر، حذف الحواشي)
LIBRARY = [
    ("sira_ibn_hisham", "sira_ibn_hisham", "السيرة النبوية لابن هشام",
     "عبد الملك بن هشام (ت ٢١٣هـ)", "سيرة", "brackets"),
    ("zad_almaad", "zad_almaad", "زاد المعاد في هدي خير العباد",
     "ابن قيم الجوزية (ت ٧٥١هـ)", "سيرة وهدي", None),
    ("bidaya", "bidaya", "البداية والنهاية",
     "ابن كثير (ت ٧٧٤هـ)", "تاريخ", "parens"),
    ("tarikh_tabari", "tarikh_tabari", "تاريخ الأمم والملوك (تاريخ الطبري)",
     "محمد بن جرير الطبري (ت ٣١٠هـ)", "تاريخ", None),
    ("alkamil", "alkamil", "الكامل في التاريخ",
     "ابن الأثير (ت ٦٣٠هـ)", "تاريخ", None),
    ("asbab_suyuti", "asbab_suyuti", "لباب النقول في أسباب النزول",
     "جلال الدين السيوطي (ت ٩١١هـ)", "علوم القرآن", None),
]

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE chapter (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    volume TEXT,
    first_page INTEGER NOT NULL
);
CREATE TABLE page (
    id INTEGER PRIMARY KEY,
    volume TEXT,
    page_num TEXT,
    chapter_id INTEGER NOT NULL,
    text TEXT NOT NULL
);
CREATE INDEX page_chapter ON page(chapter_id, id);
"""

DIGITS = "0-9٠-٩"


def strip_notes(text: str, style: str | None) -> str:
    """يحذف كتلة الحواشي في آخر الصفحة وعلاماتها داخل المتن."""
    if style == "brackets":
        block = re.compile(rf"^\[[{DIGITS}]+\]", re.M)
        marker = re.compile(rf"\s?\[[{DIGITS}]+\]")
    elif style == "parens":
        block = re.compile(rf"^\((?:[{DIGITS}]+|\*)\)", re.M)
        marker = re.compile(rf"\s?\([{DIGITS}]+\)")
    else:
        return text.strip()
    match = block.search(text)
    if match:
        text = text[: match.start()]
    return marker.sub("", text).strip()


def build(out: Path, slug: str, title: str, author: str, category: str,
          pages: list[tuple[str | None, str | None, str, str]], extra_meta: dict) -> dict:
    """pages: (volume, page_num, chapter_title, text) بالترتيب."""
    path = out / f"{slug}.sqlite"
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    chapter_id = 0
    previous = None
    page_id = 0
    for volume, page_num, chapter_title, text in pages:
        if not text.strip():
            continue
        page_id += 1
        key = (volume, chapter_title)
        if key != previous:
            chapter_id += 1
            previous = key
            db.execute("INSERT INTO chapter VALUES (?, ?, ?, ?)",
                       (chapter_id, chapter_title, volume, page_id))
        db.execute("INSERT INTO page VALUES (?, ?, ?, ?, ?)",
                   (page_id, volume, page_num, chapter_id, text))
    # التبويب في catalog.json فقط — لا يدخل الملف فتبقى بصمات الكتب المرفوعة.
    meta = {"slug": slug, "title": title, "author": author, "category": category,
            "format": str(FORMAT_VERSION), **extra_meta}
    for k, v in meta.items():
        db.execute("INSERT INTO meta VALUES (?, ?)", (k, str(v)))
    db.commit()
    db.execute("VACUUM")
    db.close()

    gz = out / f"{slug}.sqlite.gz"
    with path.open("rb") as raw, gz.open("wb") as target, gzip.GzipFile(
        filename="", mode="wb", fileobj=target, compresslevel=9, mtime=0
    ) as packed:
        packed.write(raw.read())
    entry = {
        "slug": slug, "title": title, "author": author, "category": category,
        "section": SECTIONS[category], "file": gz.name, "bytes": gz.stat().st_size,
        "sqlite_bytes": path.stat().st_size,
        "sha256": hashlib.sha256(gz.read_bytes()).hexdigest(),
        "pages": page_id, "chapters": chapter_id,
    }
    print(f"{title}: {page_id} صفحة · {chapter_id} فصلاً · "
          f"{entry['bytes'] // 1024} ك.ب مضغوطاً")
    return entry


# ---------------- الرحيق المختوم ----------------

MIRROR = str.maketrans({"(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{"})


def clean_rahiq(text: str) -> str:
    """آثار التحويل من PDF فقط: الأقواس معكوسة الاتجاه، والمسافة قبل الترقيم."""
    text = text.translate(MIRROR)
    text = text.replace("{", "﴿").replace("}", "﴾")
    text = re.sub(r"\s+([،.:؛!؟])", r"\1", text)
    text = re.sub(r"\(\s+", "(", text)
    text = re.sub(r"\s+\)", ")", text)
    text = re.sub(r"\[\s+", "[", text)
    text = re.sub(r"\s+\]", "]", text)
    text = re.sub(r"^[،.:؛]\s*", "", text)
    return re.sub(r"[ \t]{2,}", " ", text).strip()


def rahiq_pages() -> list[tuple]:
    db = sqlite3.connect(SOURCE_DIR / "rahiq-makhtum.sqlite")
    rows = db.execute("SELECT page_no, text FROM pages ORDER BY page_no").fetchall()
    # بلا فهرس فصول في المصدر: كل عشر صفحات قسم بعنوان مداها.
    out = []
    for page_no, text in rows:
        first = (page_no - 1) // 10 * 10 + 1
        last = min(first + 9, len(rows))
        title = f"الصفحات {arabic_digits(first)}–{arabic_digits(last)}"
        out.append((None, str(page_no), title, clean_rahiq(text)))
    return out


def arabic_digits(n: int) -> str:
    return "".join(chr(0x0660 + int(d)) for d in str(n))


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path,
                        default=Path(__file__).resolve().parent / "out" / "library_books")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    lib = sqlite3.connect(SOURCE_DIR / "islamic-library.sqlite")
    catalog = []
    for slug, source_id, title, author, category, notes in LIBRARY:
        info = lib.execute(
            "SELECT edition, source_name, source_url FROM books WHERE id = ?", (source_id,)
        ).fetchone()
        rows = lib.execute(
            "SELECT volume, page_num, title, text FROM book_pages WHERE book_id = ?"
            " ORDER BY page_id", (source_id,)
        ).fetchall()
        pages = [(v, p, (t or "").strip() or title, strip_notes(x, notes))
                 for v, p, t, x in rows]
        catalog.append(build(args.out, slug, title, author, category, pages, {
            "edition": info[0] or "", "source": info[1] or "", "source_url": info[2] or "",
            "license": "متن في الملك العام" + ("؛ حُذفت حواشي الطبعة" if notes else ""),
        }))

    adhkar = sqlite3.connect(ADHKAR_BOOKS)
    for slug, source_id, title, author, notes in ADHKAR:
        info = adhkar.execute(
            "SELECT editor, publisher, edition, source_url FROM books WHERE id = ?", (source_id,)
        ).fetchone()
        rows = adhkar.execute(
            "SELECT part, page_num, title, text FROM book_pages WHERE book_id = ?"
            " ORDER BY page_id", (source_id,)
        ).fetchall()
        pages = [(v, p, (t or "").strip() or title, strip_notes(x, notes))
                 for v, p, t, x in rows]
        catalog.append(build(args.out, slug, title, author, "أذكار", pages, {
            "edition": " · ".join(x for x in info[:3] if x), "source": "المكتبة الشاملة",
            "source_url": info[3] or "",
            "license": "متن في الملك العام" + ("؛ حُذفت حواشي التحقيق" if notes else ""),
        }))

    catalog.append(build(args.out, "rahiq_makhtum", "الرحيق المختوم",
                         "صفي الرحمن المباركفوري", "سيرة", rahiq_pages(), {
                             "publisher": "دار السلام",
                             "license": "منشور بإذن الناشر (دار السلام)",
                         }))
    for slug, rel, author, rights in WEST:
        src = sqlite3.connect(WEST_DIR / rel)
        title, publisher, edition, source_url = src.execute(
            "SELECT title, publisher, edition, source_url FROM books"
        ).fetchone()
        rows = src.execute(
            "SELECT page_num, part, text FROM book_pages ORDER BY page_id"
        ).fetchall()
        pages = [(None, n, (part or title).strip(), (text or "").strip())
                 for n, part, text in rows]
        catalog.append(build(args.out, slug, title, author, "الإسلام والغرب", pages, {
            "edition": " · ".join(x for x in (publisher, edition) if x),
            "source_url": source_url or "", "license": rights,
            "note": "نص رقمي منشور" if slug == "west_muslim_world"
            else "نص مستخرج آلياً (OCR) من نسخة مصوّرة — قد يقع فيه خطأ مطبعي",
        }))

    (args.out / "catalog.json").write_text(
        json.dumps({"format": FORMAT_VERSION, "books": catalog}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print("catalog.json ←", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
