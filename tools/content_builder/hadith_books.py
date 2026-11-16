#!/usr/bin/env python3
"""كتب الحديث: الصغيرة داخل التطبيق، والكبيرة ملفات تُنزَّل عند الطلب.

المصدر: fawazahmed0/hadith-api — ترخيص Unlicense (ملكية عامة)، النسخ
العربية المشكولة ``ara-*``. كل نص يُنسخ حرفياً.

    # ١) الأربعون القدسية وأربعون الدهلوي داخل content.sqlite
    python tools/content_builder/hadith_books.py bundle
    python tools/content_builder/finalize.py

    # ٢) الكتب التسعة: ملف SQLite مضغوط لكل كتاب + catalog.json
    python tools/content_builder/hadith_books.py books --out out/hadith_books

المصدر يُقرأ من ``--source`` (مجلد editions محلي) أو يُنزَّل من jsDelivr.

درجات الحديث في المصدر نص إنجليزي حر («Isnaad Sahih»، «Sahih - Agreed Upon»)؛
تُترجم بقاموس مصطلحات ثابت، وما لا يُترجم بالكامل يبقى بنصه الأصلي — لا
تخمين. اسم الحاكم يُترجم من قائمة ثابتة. ``reviewed_by`` قيد المراجعة الشرعية.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import re
import sqlite3
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.sqlite"
CDN = "https://cdn.jsdelivr.net/gh/fawazahmed0/hadith-api@1/editions"
RAW = Path(__file__).resolve().parent / "out" / "raw" / "hadith"
FORMAT_VERSION = 1

# الكتب الصغيرة داخل التطبيق (الأربعون النووية تُبنى في hadith.py).
BUNDLED = [
    ("qudsi", "qudsi40", "الأربعون القدسية"),
    ("dehlawi", "dehlawi40", "الأربعون للشاه ولي الله الدهلوي"),
]

# الكتب الكبيرة: (معرّف المصدر، المعرّف في التطبيق، الاسم العربي، الاسم الإنجليزي)
BOOKS = [
    ("bukhari", "bukhari", "صحيح البخاري", "Sahih al-Bukhari"),
    ("muslim", "muslim", "صحيح مسلم", "Sahih Muslim"),
    ("abudawud", "abudawud", "سنن أبي داود", "Sunan Abi Dawud"),
    ("tirmidhi", "tirmidhi", "جامع الترمذي", "Jami at-Tirmidhi"),
    ("nasai", "nasai", "سنن النسائي", "Sunan an-Nasai"),
    ("ibnmajah", "ibnmajah", "سنن ابن ماجه", "Sunan Ibn Majah"),
    ("malik", "malik", "موطأ مالك", "Muwatta Malik"),
]

# ---------------- درجات الحديث ----------------

# عبارات كاملة أولاً (الأطول قبل الأقصر)، ثم الكلمات المفردة.
GRADE_PHRASES = [
    ("Sahih - Agreed Upon", "صحيح - متفق عليه"),
    ("Sahih - Bukhari And Muslim", "صحيح - البخاري ومسلم"),
    ("Bukhari And Muslim", "البخاري ومسلم"),
    ("Agreed Upon", "متفق عليه"),
    ("Very Daif Isnaad", "إسناده ضعيف جداً"),
    ("Very Daif", "ضعيف جداً"),
    ("Hasan Sahih Isnaad", "حسن صحيح الإسناد"),
    ("Isnaad Sahih", "إسناده صحيح"),
    ("Isnaad Hasan", "إسناده حسن"),
    ("Isnaad Daif", "إسناده ضعيف"),
    ("Sanad Daif", "سنده ضعيف"),
    ("Sahih Isnaad", "صحيح الإسناد"),
    ("Hasan Isnaad", "حسن الإسناد"),
    ("Daif Isnaad", "ضعيف الإسناد"),
    ("Sahih Lighairihi", "صحيح لغيره"),
    ("Hasan Lighairihi", "حسن لغيره"),
    ("Sahih Bukhari", "صحيح البخاري"),
    ("Sahih Muslim", "صحيح مسلم"),
    ("Hasan Sahih", "حسن صحيح"),
]
GRADE_WORDS = {
    "Sahih": "صحيح",
    "Hasan": "حسن",
    "Daif": "ضعيف",
    "Isnaad": "الإسناد",
    "Sanad": "السند",
    "Lighairihi": "لغيره",
    "Mauquf": "موقوف",
    "Muquf": "موقوف",
    "Maqtu": "مقطوع",
    "Mursal": "مرسل",
    "Munkar": "منكر",
    "Shadh": "شاذ",
    "Mawdu": "موضوع",
    "Batil": "باطل",
    "Mutawatir": "متواتر",
    "Hadith": "الحديث",
    "Matn": "المتن",
    "Witness": "شاهد",
    "After": "بعد",
    "Mukhtasar": "مختصراً",
    "Malool": "معلول",
    "Bukhari": "البخاري",
    "Muslim": "مسلم",
}
GRADERS = {
    "Al-Albani": "الألباني",
    "Zubair Ali Zai": "زبير علي زئي",
    "Shuaib Al Arnaut": "شعيب الأرناؤوط",
    "Abu Ghuddah": "أبو غدة",
    "Muhammad Muhyi Al-Din Abdul Hamid": "محمد محيي الدين عبد الحميد",
    "Muhammad Fouad Abd al-Baqi": "محمد فؤاد عبد الباقي",
    "Ahmad Muhammad Shakir": "أحمد محمد شاكر",
    "Bashar Awad Maarouf": "بشار عواد معروف",
    "Salim al-Hilali": "سليم الهلالي",
}

# تصنيف الدرجة للون الشارة: أول مصطلح يرد في النص.
CATEGORY_TERMS = [
    ("Mawdu", "mawdu"),
    ("Batil", "mawdu"),
    ("Very Daif", "daif"),
    ("Daif", "daif"),
    ("Munkar", "daif"),
    ("Shadh", "daif"),
    ("Hasan", "hasan"),
    ("Sahih", "sahih"),
]


def grade_arabic(raw: str) -> str:
    """ترجمة مصطلح الدرجة؛ يعيد النص الأصلي إن بقي فيه ما لا يُترجم."""
    text = raw.strip()
    if not text or text == "-":
        return text
    out = text
    for english, arabic in GRADE_PHRASES:
        out = re.sub(rf"\b{re.escape(english)}\b", arabic, out)
    for english, arabic in GRADE_WORDS.items():
        out = re.sub(rf"\b{english}\b", arabic, out)
    out = re.sub(r"\s+", " ", out).strip()
    return text if re.search(r"[A-Za-z]", out) else out


def grade_category(raw: str) -> str:
    # «حسن صحيح» (اصطلاح الترمذي) من مرتبة الصحيح.
    if re.match(r"\s*Hasan Sahih\b", raw):
        return "sahih"
    best = None
    for term, category in CATEGORY_TERMS:
        match = re.search(rf"\b{term}\b", raw)
        if match and (best is None or match.start() < best[0]):
            best = (match.start(), category)
    return best[1] if best else "other"


# ---------------- البحث ----------------

DIACRITICS = re.compile("[ؐ-ًؚ-ٰٟۖ-ۭـ]")
LETTERS = str.maketrans({
    "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
    "ى": "ي", "ئ": "ي", "ؤ": "و", "ة": "ه", "ء": None,
})
NON_ARABIC = re.compile(r"[^ء-ي\s]")


def normalize(text: str) -> str:
    """نفس تطبيع التطبيق (recitation_matcher.normalizeForMatch) للبحث."""
    text = DIACRITICS.sub("", text).translate(LETTERS)
    text = NON_ARABIC.sub(" ", text)
    return re.sub(r"\s+", " ", text).strip()


def search_body(text: str) -> str:
    """نص الفهرس: كل كلمة ومعها صيغها بلا السوابق الملتصقة.

    «بالنيات» تُفهرس أيضاً «النيات» و«نيات»، فيجدها من يبحث عن «النيات».
    التطبيق يحذف «ال» من أول كلمة البحث (HadithBookDb.search).
    """
    out = []
    for word in normalize(text).split():
        forms = [word]
        rest = word
        for prefix in ("[وف]", "[بلك]", "ال"):
            match = re.match(f"^{prefix}(.{{2,}})$", rest)
            if match:
                rest = match.group(1)
                forms.append(rest)
        out.extend(dict.fromkeys(forms))
    return " ".join(out)


# ---------------- المصدر ----------------

def load(edition: str, source: Path | None) -> dict:
    name = f"ara-{edition}.min.json"
    if source is not None and (source / name).exists():
        path = source / name
    else:
        RAW.mkdir(parents=True, exist_ok=True)
        path = RAW / name
        if not path.exists():
            print("تنزيل:", f"{CDN}/{name}")
            request = urllib.request.Request(
                f"{CDN}/{name}", headers={"User-Agent": "YousufBuilder/0.3"}
            )
            with urllib.request.urlopen(request, timeout=300) as response:
                path.write_bytes(response.read())
    return json.loads(path.read_text(encoding="utf-8-sig"))


def clean(text: str) -> str:
    return text.replace("﻿", "").replace("‏", "").strip()


def number_text(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else str(value)


# ---------------- ١) المضمَّن ----------------

def bundle(db_path: Path, source: Path | None) -> None:
    db = sqlite3.connect(db_path)
    for edition, slug, name in BUNDLED:
        payload = load(edition, source)
        hadiths = [h for h in payload["hadiths"] if clean(h.get("text") or "")]
        db.execute(
            "INSERT INTO hadith_book (slug, name_ar, total) VALUES (?, ?, ?)"
            " ON CONFLICT(slug) DO UPDATE SET name_ar = excluded.name_ar,"
            " total = excluded.total",
            (slug, name, len(hadiths)),
        )
        book_id = db.execute(
            "SELECT id FROM hadith_book WHERE slug = ?", (slug,)
        ).fetchone()[0]
        db.execute("DELETE FROM hadith WHERE book_id = ?", (book_id,))
        for item in hadiths:
            db.execute(
                "INSERT INTO hadith (book_id, number, text_ar) VALUES (?, ?, ?)",
                (book_id, int(item["hadithnumber"]), clean(item["text"])),
            )
        print(f"{name}: {len(hadiths)} حديثاً")
    db.commit()
    db.close()


# ---------------- ٢) الكتب الكبيرة ----------------

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE section (
    id INTEGER PRIMARY KEY,
    name_en TEXT NOT NULL,
    first_number REAL,
    last_number REAL,
    total INTEGER NOT NULL
);
CREATE TABLE hadith (
    id INTEGER PRIMARY KEY,
    number TEXT NOT NULL,
    arabic_number TEXT,
    section_id INTEGER NOT NULL,
    text TEXT NOT NULL
);
CREATE INDEX hadith_section ON hadith(section_id, id);
CREATE TABLE grade (
    hadith_id INTEGER NOT NULL,
    grade_ar TEXT NOT NULL,
    grade_raw TEXT NOT NULL,
    category TEXT NOT NULL,
    grader_ar TEXT NOT NULL
);
CREATE INDEX grade_hadith ON grade(hadith_id);
CREATE VIRTUAL TABLE hadith_fts USING fts5(body, content='', columnsize=0, detail=column);
"""


def build_book(edition: str, slug: str, name_ar: str, name_en: str,
               source: Path | None, out: Path) -> dict:
    payload = load(edition, source)
    meta = payload["metadata"]
    sections = meta.get("sections", {})
    details = meta.get("section_details", {})

    path = out / f"{slug}.sqlite"
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)

    # القسم الذي يقع فيه رقم الحديث.
    ranges = []
    for key, detail in details.items():
        first = detail.get("hadithnumber_first") or 0
        last = detail.get("hadithnumber_last") or 0
        if int(key) > 0 and last >= first > 0:
            ranges.append((int(key), first, last))

    # الحديث بين نطاقين (فجوة في المصدر) يتبع أقرب قسم قبله.
    ranges.sort(key=lambda r: r[1])

    def section_of(number: float) -> int:
        chosen = ranges[0][0] if ranges else 0
        for key, first, _ in ranges:
            if first <= number:
                chosen = key
            else:
                break
        return chosen

    counts: dict[int, int] = {}
    unmapped: dict[str, int] = {}
    row = 0
    for item in payload["hadiths"]:
        text = clean(item.get("text") or "")
        if not text:
            continue
        row += 1
        number = float(item["hadithnumber"])
        section = section_of(number)
        counts[section] = counts.get(section, 0) + 1
        db.execute(
            "INSERT INTO hadith (id, number, arabic_number, section_id, text)"
            " VALUES (?, ?, ?, ?, ?)",
            (row, number_text(number),
             number_text(float(item.get("arabicnumber") or number)), section, text),
        )
        db.execute("INSERT INTO hadith_fts (rowid, body) VALUES (?, ?)",
                   (row, search_body(text)))
        for grade in item.get("grades") or []:
            raw = (grade.get("grade") or "").strip()
            if not raw or raw == "-":
                continue
            arabic = grade_arabic(raw)
            if arabic == raw:
                unmapped[raw] = unmapped.get(raw, 0) + 1
            grader = (grade.get("name") or "").strip()
            db.execute(
                "INSERT INTO grade VALUES (?, ?, ?, ?, ?)",
                (row, arabic, raw, grade_category(raw), GRADERS.get(grader, grader)),
            )

    for key, total in sorted(counts.items()):
        first = details.get(str(key), {}).get("hadithnumber_first")
        last = details.get(str(key), {}).get("hadithnumber_last")
        db.execute(
            "INSERT INTO section VALUES (?, ?, ?, ?, ?)",
            (key, (sections.get(str(key)) or "").strip(), first, last, total),
        )
    for key, value in {
        "slug": slug,
        "name_ar": name_ar,
        "name_en": name_en,
        "format": str(FORMAT_VERSION),
        "count": str(row),
        "source": "fawazahmed0/hadith-api ara-" + edition,
        "license": "Unlicense (public domain)",
    }.items():
        db.execute("INSERT INTO meta VALUES (?, ?)", (key, value))
    db.execute("INSERT INTO hadith_fts(hadith_fts) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()

    gz = out / f"{slug}.sqlite.gz"
    # mtime=0 وبلا اسم ملف: ضغط قابل للتكرار، فتبقى البصمة ثابتة بين البناءات.
    with path.open("rb") as raw, gz.open("wb") as target, gzip.GzipFile(
        filename="", mode="wb", fileobj=target, compresslevel=9, mtime=0
    ) as packed:
        packed.write(raw.read())
    digest = hashlib.sha256(gz.read_bytes()).hexdigest()
    entry = {
        "slug": slug,
        "name_ar": name_ar,
        "name_en": name_en,
        "file": gz.name,
        "bytes": gz.stat().st_size,
        "sqlite_bytes": path.stat().st_size,
        "sha256": digest,
        "count": row,
        "graded": bool(
            sqlite3.connect(path).execute("SELECT 1 FROM grade LIMIT 1").fetchone()
        ),
    }
    print(f"{name_ar}: {row} حديثاً · {entry['bytes'] // 1024} ك.ب مضغوطاً"
          f" · درجات غير مترجمة: {sum(unmapped.values())}")
    for raw, n in sorted(unmapped.items(), key=lambda t: -t[1])[:5]:
        print("   ", n, raw)
    return entry


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["bundle", "books"])
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--source", type=Path, default=None,
                        help="مجلد editions محلي من hadith-api")
    parser.add_argument("--out", type=Path,
                        default=Path(__file__).resolve().parent / "out" / "hadith_books")
    args = parser.parse_args()

    if args.command == "bundle":
        bundle(args.db, args.source)
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    catalog = [build_book(*book, args.source, args.out) for book in BOOKS]
    (args.out / "catalog.json").write_text(
        json.dumps({"format": FORMAT_VERSION, "books": catalog},
                   ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print("catalog.json ←", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
