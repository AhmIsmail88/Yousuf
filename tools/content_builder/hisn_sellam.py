#!/usr/bin/env python3
"""«حصن المسلم» في تبويب الأذكار — من قاعدة asellam/HisnElMuslim (MIT).

    python tools/content_builder/hisn_sellam.py [--db assets/db/content.sqlite] [--dry-run]
    python tools/content_builder/finalize.py

المصدر: ``sources/hisn_sellam/hisn_almuslim.sqlite`` — نسخة SQL من مستودع
asellam/HisnElMuslim (رخصة MIT، نقله صاحبه من الطبعة المطبوعة وقابله بنسخ
أخرى)، مع التوثيق في المجلد نفسه (LICENSE.md، NOTICE.md، SOURCE.md). نص
الكتاب للمؤلف د. سعيد بن وهف القحطاني رحمه الله، ويُوزَّع مجاناً.

لماذا بدل المصدر السابق: الصباح والمساء بابان منفصلان في المصدر نفسه بلفظ
كل منهما، والتشكيل كامل، والتخريج لكل ذكر، وعدد التكرار من المصدر.

ما يفعله السكربت (نقل وتقسيم لكلمات المصدر فقط — لا نص من عندنا):
1. يحذف أبواب حصن المسلم القديمة ويُبقي «أدعية من القرآن» (نص المصحف)
   بعدها في الترتيب.
2. يتخطى «المقدمة» و«فضل الذكر» (ليسا أذكاراً تُعدّ)، وسطر افتتاح بابَي
   الصباح والمساء («الحمد لله وحده…») لأنه تمهيد لا ذكر.
3. الآيات داخل {…} تُستبدل بنص المصحف العثماني (Tanzil) بأرقامها.
4. الذكر الذي فيه أكثر من عدد («… (ثلاثاً وثلاثين مرة) … (مرة واحدة)»)
   يُقسَّم عدّادات بألفاظه نفسها، وكل عدد في عدّاده.
5. القوس الأخير غير العددي («(بعد صلاة المغرب والصبح)») يُنقل إلى عمود
   التعليمة ويبقى المعنى كما هو.
6. التخريج يوضع في عمود المصدر.
"""

from __future__ import annotations

import argparse
import re
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from adhkar_fix import QuranIndex, normalize, quran_text  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.sqlite"
SOURCE = Path(__file__).resolve().parent / "sources" / "hisn_sellam" / "hisn_almuslim.sqlite"

# الأبواب التي تظهر شرائح سريعة (slug ثابت تقرؤه الواجهة والرئيسية والأطفال).
FEATURED = {
    "اذكار الصباح": "morning",
    "اذكار المساء": "evening",
    "اذكار النوم": "sleep",
    "اذكار الاستيقاظ من النوم": "wake",
    "الاذكار بعد السلام من الصلاه": "after_prayer",
    "دعاء الهم والحزن": "distress",
    "دعاء السفر": "travel",
}
SKIP = {"المقدمه", "فضل الذكر"}

HARAKAT = re.compile("[ً-ْٰـ]")
COUNT_WORDS = (("مائة", 100), ("مائه", 100), ("مئة", 100), ("عشر", 10), ("سبع", 7),
               ("أربع", 4), ("اربع", 4), ("ثلاث", 3), ("مرتين", 2), ("واحدة", 1), ("واحده", 1))
COUNT_HINT = re.compile(r"مر[ةه]|مرات|مرار|ثلاث|سبع|عشر|مائ|أربع|اربع|مرتين")


def plain(text: str) -> str:
    return HARAKAT.sub("", text).strip()


def count_of(note: str) -> int | None:
    """عدد التكرار من تعليمة المصدر («ثلاثاً وثلاثين مرة» = ٣٣)."""
    n = plain(note)
    if "وثلاثين" in n:
        return 34 if ("أربع" in n or "اربع" in n) else 33
    for word, value in COUNT_WORDS:
        if word in n:
            return value
    return None


def is_count(note: str) -> bool:
    n = plain(note)
    return len(n) < 30 and bool(COUNT_HINT.search(n)) and count_of(n) is not None


def tidy(text: str) -> str:
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.split("\n")]
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


def split_counts(text: str, repeat: int) -> list[tuple[str, int, str | None]]:
    """[(نص، تكرار، تعليمة)] — يقسم عند أقواس العدد إن كان فيه أكثر من عدد."""
    parens = list(re.finditer(r"\(([^()]*)\)", text))

    def qualifies(m: re.Match) -> bool:
        # عدد في آخر سطر يعود على السطر كله؛ وفي وسط السطر لا يُقسَّم إلا بعد
        # عبارة قصيرة («أستغفر الله (ثلاثاً)، …») — وإلا فقد يعود على جزء منها
        # فقط (دعاء الاستفتاح) فيبقى النص كما هو.
        if not is_count(m.group(1)):
            return False
        after = text[m.end():]
        if not after.strip(" ،.") or after.lstrip(" ،.").startswith("\n"):
            return True
        line_start = text.rfind("\n", 0, m.start()) + 1
        before = re.split(r"[()]", text[line_start:m.start()])[-1]
        return len(before.split()) <= 4

    counted = [m for m in parens if is_count(m.group(1))]
    if not all(qualifies(m) for m in counted):
        return [(text, repeat, None)]
    pieces: list[tuple[str, int, str | None]] = []
    if counted and (len(counted) > 1 or text[counted[0].end():].strip(" ،.\n")):
        start = 0
        for m in counted:
            body = text[start:m.start()].strip(" ،.\n")
            if body:
                pieces.append((body, count_of(m.group(1)) or 1, plain(m.group(1))))
            start = m.end()
        rest = text[start:].strip(" ،.\n")
        if rest:
            pieces.append((rest, 1, None))
        return pieces
    if counted:  # عدد واحد في آخر النص
        m = counted[0]
        return [(text[:m.start()].strip(" ،.\n"), count_of(m.group(1)) or repeat, plain(m.group(1)))]
    # قوس أخير قصير غير عددي = تعليمة (بعد صلاة كذا…) — ليس كلاماً يُقال.
    m = re.search(r"\n\s*\(([^()]{3,40})\)\s*$", text)
    if m and not re.search(r"قل|يقول|فليقل", plain(m.group(1))):
        return [(text[:m.start()].strip(" ،.\n"), repeat, plain(m.group(1)))]
    return [(text, repeat, None)]


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    src = sqlite3.connect(args.source)
    db = sqlite3.connect(args.db)
    quran = QuranIndex(db)
    report: list[str] = []

    old = [r[0] for r in db.execute("SELECT id FROM dhikr_category WHERE slug <> 'quranic'")]
    db.executemany("DELETE FROM dhikr WHERE category_id = ?", [(i,) for i in old])
    db.executemany("DELETE FROM dhikr_category WHERE id = ?", [(i,) for i in old])

    chapters = src.execute(
        "SELECT id, chapter_number, title FROM categories ORDER BY chapter_number"
    ).fetchall()
    total = 0
    sort = 0
    for cat_id, number, title in chapters:
        key = normalize(title)
        if key in SKIP:
            continue
        sort += 1
        slug = FEATURED.get(key, f"hisn-{number:03d}")
        name = plain(title)
        cur = db.execute(
            "INSERT INTO dhikr_category (slug, name, sort) VALUES (?, ?, ?)", (slug, name, sort)
        )
        new_cat = cur.lastrowid
        rows = src.execute(
            "SELECT position, text, repeat_count, reference, footnote FROM adhkar"
            " WHERE category_id = ? ORDER BY position", (cat_id,)
        ).fetchall()
        for position, text, repeat, reference, footnote in rows:
            if slug in ("morning", "evening") and position == 1 and normalize(text).startswith(
                "الحمد لله وحده"
            ):
                report.append(f"· تخطي تمهيد باب {name}")
                continue

            def replace(match: re.Match) -> str:
                ayat = quran.match(match.group(1))
                if ayat is None:
                    report.append(f"⚠ آية لم تُطابَق ({name}): {match.group(1)[:40]}…")
                    return match.group(0)
                return quran_text(ayat)

            text = tidy(re.sub(r"\{([^{}]+)\}", replace, text.replace("\r", "")))
            source = tidy(" ".join(x for x in (reference, footnote) if x)) or (
                f"حصن المسلم — باب: {name}"
            )
            pieces = split_counts(text, repeat)
            if len(pieces) > 1:
                report.append(f"✓ تقسيم ({name}): " + " + ".join(str(p[1]) for p in pieces))
            for body, count, instruction in pieces:
                db.execute(
                    "INSERT INTO dhikr (category_id, text, repeat_count, source, instruction)"
                    " VALUES (?, ?, ?, ?, ?)",
                    (new_cat, body, count, source, instruction),
                )
                total += 1

    # «أدعية من القرآن» بعد أبواب حصن المسلم في فهرس كل الأقسام.
    db.execute("UPDATE dhikr_category SET sort = ? WHERE slug = 'quranic'", (sort + 1,))
    db.execute(
        "INSERT OR REPLACE INTO meta (key, value) VALUES ('adhkar_source', ?)",
        ("حصن المسلم — د. سعيد بن وهف القحطاني؛ البيانات: asellam/HisnElMuslim (MIT)",),
    ) if db.execute("SELECT 1 FROM sqlite_master WHERE name = 'meta'").fetchone() else None

    for line in report:
        print(line)
    print(f"الأبواب: {sort} · الأذكار: {total}")
    if args.dry_run:
        db.rollback()
        print("— تجربة فقط —")
    else:
        db.commit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
