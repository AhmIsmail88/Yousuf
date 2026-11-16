"""تصحيحات آلية لمتن الأذكار المستورد — بلا أي نص شرعي جديد.

    python tools/content_builder/adhkar_fix.py [--db assets/db/content.sqlite] [--dry-run]
    python tools/content_builder/finalize.py

ما تفعله (كله نقل أو تقسيم لكلمات المصدر نفسه، ويُراجَع مع الشيخ):

1. عمود `instruction`: التعليمات المكتوبة داخل النص بين قوسين في آخره
   («( ثلاث مرات )»، «( إذا أصبح )»…) تُنقل إليه ويُحذف من نص الذكر.
2. عدد التكرار يُؤخذ من تلك التعليمات (ثلاث=٣، سبع=٧، أربع=٤، عشر=١٠،
   مائة=١٠٠) — يصحّح أذكاراً كان عدّادها يكتمل قبل وقته.
3. فصل «أذكار الصباح» عن «أذكار المساء» (كانا باباً واحداً):
   - مقدمة الباب «الحمد لله وحده…» ليست ذكراً فتُحذف.
   - ما ذكر المصدر لفظ مسائه صراحة («وإذا أمسى فليقل: …») يأخذ ذلك اللفظ
     حرفياً في المساء.
   - المقيّد بـ«إذا أصبح» للصباح فقط، وبـ«إذا أمسى» للمساء فقط.
4. التسبيح المجمّع (٣٣/٣٣/٣٤) يُقسَّم عدّادات مستقلة بألفاظه نفسها.
5. الآيات داخل الأذكار ({…}) تُستبدل بنص المصحف العثماني من جدول ayah
   (Tanzil) — شرط «النسخ الحرفي» — مع أرقام الآيات.

القاعدة تبقى `reviewed_by = NULL` حتى توقيع المراجع (SPEC §4).
"""

from __future__ import annotations

import argparse
import difflib
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.sqlite"

COUNT_WORDS = [
    ("مائة", 100),
    ("عشر", 10),
    ("سبع", 7),
    ("أربع", 4),
    ("ثلاث", 3),
    ("مرتين", 2),
]

DIACRITICS = re.compile("[ؐ-ًؚ-ٰٟۖ-ۭـ]")


def normalize(text: str) -> str:
    text = DIACRITICS.sub("", text)
    for a, b in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ٱ", "ا"), ("ى", "ي"), ("ة", "ه"), ("ـ", "")):
        text = text.replace(a, b)
    return re.sub(r"\s+", " ", re.sub(r"[^ء-ي ]", " ", text)).strip()


def count_of(note: str) -> int | None:
    if "وثلاثين" in note:
        return 34 if "أربع" in note else 33
    for word, value in COUNT_WORDS:
        if word in note:
            return value
    return None


def to_arabic_digits(n: int) -> str:
    return "".join(chr(0x0660 + int(d)) for d in str(n))


class QuranIndex:
    """مطابقة مقطع قرآني مكتوب بإملاء آخر بآيات المصحف."""

    def __init__(self, db: sqlite3.Connection):
        self.rows = db.execute(
            "SELECT id, surah_id, number, text_uthmani, text_simple FROM ayah ORDER BY id"
        ).fetchall()
        basmala = "بسم الله الرحمن الرحيم "

        def clean(row: tuple) -> str:
            text = normalize(row[4])
            # أول آية في كل سورة (عدا الفاتحة) تبدأ بالبسملة في نص المصدر.
            if row[2] == 1 and row[1] != 1 and text.startswith(basmala):
                text = text[len(basmala):]
            return text

        self.norm = [clean(r) for r in self.rows]

    def match(self, segment: str) -> list[tuple] | None:
        """يعيد آيات متتالية يطابق مجموعها المقطع (تشابه ≥ ٩٠٪)، أو None.

        المصادر تكتب الآيات بإملاء مختلف قليلاً (شاء/شآء، يؤوده/يئوده)،
        فالمطابقة تقريبية على النص المطبّع، ثم يُستبدل بالنص العثماني كاملاً.
        """
        target = normalize(segment.replace("*", " "))
        if len(target) < 8:
            return None
        head = target.split()[:2]
        best: tuple[float, list[tuple]] | None = None
        for i, text in enumerate(self.norm):
            words = text.split()
            if words[:2] != head and words[:1] != head[:1]:
                continue
            acc = ""
            for j in range(i, min(i + 30, len(self.rows))):
                acc = (acc + " " + self.norm[j]).strip()
                if len(acc) >= len(target) * 0.85:
                    ratio = difflib.SequenceMatcher(None, acc, target).ratio()
                    if ratio >= 0.9 and (best is None or ratio > best[0]):
                        best = (ratio, self.rows[i : j + 1])
                if len(acc) > len(target) * 1.15:
                    break
        return best[1] if best else None


def quran_text(ayat: list[tuple]) -> str:
    """نص الآيات العثماني (Tanzil) بأرقامها، بلا البسملة الملحقة بأول السورة."""

    def text(a: tuple) -> str:
        value = a[3].strip().lstrip("﻿")
        if a[2] == 1 and a[1] not in (1, 9):
            words = value.split()
            if normalize(" ".join(words[:4])) == "بسم الله الرحمن الرحيم":
                value = " ".join(words[4:])
        return value

    return " ".join(f"{text(a)} ﴿{to_arabic_digits(a[2])}﴾" for a in ayat)


def main() -> int:
    parser = argparse.ArgumentParser(description="تصحيحات آلية للأذكار")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    db = sqlite3.connect(args.db)
    columns = [r[1] for r in db.execute("PRAGMA table_info(dhikr)")]
    if "instruction" not in columns:
        db.execute("ALTER TABLE dhikr ADD COLUMN instruction TEXT")
    report: list[str] = []
    quran = QuranIndex(db)

    # ---- ٥. الآيات داخل الأذكار ----
    for dhikr_id, text in db.execute("SELECT id, text FROM dhikr WHERE text LIKE '%{%'").fetchall():
        def replace(match: re.Match) -> str:
            ayat = quran.match(match.group(1))
            if ayat is None:
                report.append(f"⚠ آية لم تُطابَق في الذكر {dhikr_id}: {match.group(1)[:50]}…")
                return match.group(0)
            return " " + quran_text(ayat) + " "

        new = re.sub(r"\s+", " ", re.sub(r"\{([^{}]+)\}", replace, text)).strip()
        # «بسم الله الرحمن الرحيم» المكتوبة قبل السور تُترك كما في المصدر.
        if new != text:
            db.execute("UPDATE dhikr SET text = ? WHERE id = ?", (new, dhikr_id))
            report.append(f"✓ نص قرآني من المصحف في الذكر {dhikr_id}")

    # التسبيح ٣٣/٣٣/٣٤ في نص واحد بأقواس داخلية.
    for dhikr_id, cat, text, source in db.execute(
        "SELECT id, category_id, text, source FROM dhikr WHERE text LIKE '%( ثلاثاً وثلاثين )%والله أكبر%'"
    ).fetchall():
        pieces = re.findall(r"([^()]+?)\s*\(\s*([^()]+)\s*\)", text)
        if len(pieces) != 3:
            continue
        for index, (phrase, note) in enumerate(pieces):
            phrase = phrase.strip(" ،").removeprefix("و") if index else phrase.strip(" ،")
            if index == 0:
                db.execute(
                    "UPDATE dhikr SET text = ?, repeat_count = ?, instruction = ? WHERE id = ?",
                    (phrase, count_of(note), note.strip(), dhikr_id),
                )
            else:
                db.execute(
                    "INSERT INTO dhikr (category_id, text, repeat_count, source, instruction) VALUES (?, ?, ?, ?, ?)",
                    (cat, phrase, count_of(note), source, note.strip()),
                )
        report.append(f"✓ تقسيم التسبيح {dhikr_id} إلى ٣٣/٣٣/٣٤")

    # ---- ١ و٢. التعليمات وعدد التكرار ----
    trailing = re.compile(r"\s*((?:\(\s*[^()]*\)\s*)+)\s*[.،]?\s*$")
    for dhikr_id, text, repeat in db.execute("SELECT id, text, repeat_count FROM dhikr").fetchall():
        m = trailing.search(text)
        notes: list[str] = []
        body = text
        if m:
            parts = [p.strip() for p in re.findall(r"\(([^()]*)\)", m.group(1))]
            # لا ننقل أقواساً تحوي نصاً قرآنياً أو كلمة من الذكر نفسه.
            if all(len(p) < 40 and "ٱ" not in p for p in parts):
                notes = parts
                body = text[: m.start()].rstrip(" ،.")
        else:
            tail = re.search(r"[،,]?\s*(ثلاث مرات|سبع مرات)\s*\.?$", text)
            if tail:
                notes = [tail.group(1)]
                body = text[: tail.start()].rstrip(" ،.")
        if not notes:
            continue
        new_count = None
        for note in notes:
            value = count_of(note)
            if value:
                new_count = value
                break
        instruction = " · ".join(notes)
        db.execute(
            "UPDATE dhikr SET text = ?, instruction = ?, repeat_count = ? WHERE id = ?",
            (body, instruction, new_count or repeat, dhikr_id),
        )
        if new_count and new_count != repeat:
            report.append(f"✓ عدد التكرار {dhikr_id}: {repeat} → {new_count} ({instruction})")

    # ---- ٤. التسبيح المجمّع ----
    for dhikr_id, cat, text in db.execute(
        "SELECT id, category_id, text FROM dhikr WHERE text LIKE '%سبحان الله%الحمد لله%الله أكبر%'"
    ).fetchall():
        source = db.execute("SELECT source FROM dhikr WHERE id = ?", (dhikr_id,)).fetchone()[0]
        if re.fullmatch(r"\s*سبحان الله\s*والحمد لله\s*والله أكبر\s*", text.replace("،", " ")):
            continue
        if "لا إله إلا الله وحده لا شريك له" in text and text.startswith("سبحان الله ، والحمد لله ، والله أكبر"):
            head, _, tail = text.partition("لا إله إلا الله")
            db.execute(
                "UPDATE dhikr SET text = ?, repeat_count = 33, instruction = ? WHERE id = ?",
                (head.strip(" ،"), "ثلاثاً وثلاثين", dhikr_id),
            )
            db.execute(
                "INSERT INTO dhikr (category_id, text, repeat_count, source, instruction) VALUES (?, ?, 1, ?, ?)",
                (cat, ("لا إله إلا الله" + tail).strip(), source, "تمام المائة"),
            )
            report.append(f"✓ تقسيم التسبيح {dhikr_id} إلى ٣٣ + ١")
        elif text.strip().startswith("سبحان الله") and "أربعاً وثلاثين" in (
            db.execute("SELECT instruction FROM dhikr WHERE id = ?", (dhikr_id,)).fetchone()[0] or text
        ):
            pass

    # ---- ٣. الصباح والمساء ----
    morning = db.execute("SELECT id, sort FROM dhikr_category WHERE slug = 'morning'").fetchone()
    if morning and not db.execute("SELECT 1 FROM dhikr_category WHERE slug = 'evening'").fetchone():
        morning_id, sort = morning
        db.execute("UPDATE dhikr_category SET name = 'أذكار الصباح' WHERE id = ?", (morning_id,))
        db.execute("UPDATE dhikr_category SET sort = sort + 1 WHERE sort > ?", (sort,))
        cur = db.execute(
            "INSERT INTO dhikr_category (slug, name, sort) VALUES ('evening', 'أذكار المساء', ?)",
            (sort + 1,),
        )
        evening_id = cur.lastrowid
        rows = db.execute(
            "SELECT id, text, repeat_count, source, virtue, instruction FROM dhikr WHERE category_id = ? ORDER BY id",
            (morning_id,),
        ).fetchall()
        for dhikr_id, text, repeat, source, virtue, instruction in rows:
            note = instruction or ""
            if text.startswith("الحمد لله وحده") and len(text) < 70:
                db.execute("DELETE FROM dhikr WHERE id = ?", (dhikr_id,))
                report.append(f"✓ حذف مقدمة الباب {dhikr_id}")
                continue
            evening_text = text
            evening_note = note
            split = re.search(r"\s*وإذا أمس[يى]\s*(فليقل|قال ذلك أيضا)\s*:\s*", text)
            if split:
                morning_text = text[: split.start()].rstrip(" ،.")
                after = text[split.end():].rstrip(" ،.")
                db.execute("UPDATE dhikr SET text = ? WHERE id = ?", (morning_text, dhikr_id))
                if split.group(1) == "فليقل":
                    # المصدر ذكر لفظ المساء كاملاً — يُنقل حرفياً.
                    evening_text = after
                else:
                    evening_text = morning_text
                    evening_note = " · ".join(
                        x for x in (note, f"وإذا أمسى قال ذلك أيضاً: {after}") if x
                    )
            morning_only = "إذا أصبح" in note
            evening_only = "إذا أمسى" in note
            if evening_only:
                db.execute("UPDATE dhikr SET category_id = ? WHERE id = ?", (evening_id, dhikr_id))
                continue
            if morning_only:
                continue
            if not split and "أصبح" in text:
                evening_note = " · ".join(
                    x for x in (note, "في المساء يُقال بلفظ المساء — قيد المراجعة") if x
                )
            db.execute(
                "INSERT INTO dhikr (category_id, text, repeat_count, source, virtue, instruction) VALUES (?, ?, ?, ?, ?, ?)",
                (evening_id, evening_text, repeat, source, virtue, evening_note or None),
            )
        report.append("✓ فصل أذكار الصباح عن أذكار المساء")

    for line in report:
        print(line)
    if args.dry_run:
        db.rollback()
        print("— تجربة فقط، لم يُحفظ شيء —")
    else:
        db.commit()
    db.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
