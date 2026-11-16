"""نص الأذكار القرآنية من المصحف نفسه (جدول `ayah`) — حرفاً بحرف.

كانت الأدعية والآيات في الأذكار منقولة من مصدر آخر برسم عثماني مختلف قليلاً
(علامات تنوين ۭ وغيرها)، فلا تطابق نص المصحف في التطبيق. هذه الأداة تعيد كتابة
الجزء القرآني من كل ذكر من جدول `ayah` (Tanzil)، وتُبقي ما قبله وما بعده من
كلام الذكر (مثل «أعوذ بالله من الشيطان الرجيم» أو «ثلاث مرات») كما هو.

    python tools/content_builder/quran_adhkar.py [--db assets/db/content.sqlite]
    python tools/content_builder/finalize.py

القواعد:
- أرقام الآيات بعد كل آية ﴿١٢﴾ بالأرقام المشرقية.
- السورة التي تبدأ من آيتها الأولى: البسملة (من نص المصحف) في سطر وحدها.
- عدة سور في ذكر واحد (المعوذات): كل سورة في فقرة.
"""

from __future__ import annotations

import argparse
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.sqlite"

MUAWWIDHAT = [(112, 1, 4), (113, 1, 5), (114, 1, 6)]
KURSI = [(2, 255, 255)]

# أذكار مركّبة: المعرّف ← (النص القرآني الذي يُستبدل، المقدّمة النصّية قبله).
# ما بعد آخر رقم آية ﴿…﴾ في النص الأصلي يبقى ذيلاً كما هو.
COMPOSITE: dict[int, tuple[list[tuple[int, int, int]], str]] = {
    41: ([(3, 190, 200)], ""),
    111: (MUAWWIDHAT, ""),
    119: (MUAWWIDHAT, ""),
    322: (MUAWWIDHAT, ""),
    142: (MUAWWIDHAT, "يجمع كفيه ثم ينفث فيهما فيقرأ:"),
    112: (KURSI, ""),
    143: (KURSI, ""),
    118: (KURSI, "أعوذ بالله من الشيطان الرجيم"),
    321: (KURSI, "أعوذ بالله من الشيطان الرجيم"),
    144: ([(2, 285, 286)], ""),
    182: ([(57, 3, 3)], "يقرأ قوله تعالى:"),
}

# جزء من آية داخل دعاء: المعرّف ← (سورة، آية، ترتيب الكلمة التي يبدأ منها المقتطف).
PARTIAL: dict[int, tuple[int, int, int]] = {
    285: (2, 201, 3),  # «رَبَّنَآ ءَاتِنَا فِى ٱلدُّنْيَا حَسَنَةً…»
}

SIMPLE_SOURCE = re.compile(r"^سورة (.+?) · آية (\d+)$")
DIACRITICS = re.compile(r"[ً-ٰٟۖ-ۭـ]")


def arabic_digits(n: int) -> str:
    return "".join(chr(0x0660 + int(d)) for d in str(n))


def plain(name: str) -> str:
    name = DIACRITICS.sub("", name).replace("آ", "ا").replace("ۡ", "")
    return name.removeprefix("سورة ").strip()


class Mushaf:
    def __init__(self, db: sqlite3.Connection) -> None:
        self.db = db
        self.basmala = self.ayah(1, 1)
        self.surah_ids = {
            plain(name): sid for sid, name in db.execute("SELECT id, name_ar FROM surah")
        }

    def ayah(self, surah: int, number: int) -> str:
        row = self.db.execute(
            "SELECT text_uthmani FROM ayah WHERE surah_id = ? AND number = ?",
            (surah, number),
        ).fetchone()
        if row is None:
            raise KeyError(f"{surah}:{number}")
        return row[0].replace("﻿", "").replace("‏", "").strip()

    def passage(self, ranges: list[tuple[int, int, int]]) -> str:
        blocks = []
        for surah, first, last in ranges:
            lines = []
            ayat = []
            for number in range(first, last + 1):
                text = self.ayah(surah, number)
                if number == 1 and surah not in (1, 9) and text.startswith(self.basmala):
                    lines.append(self.basmala)
                    text = text[len(self.basmala):].strip()
                ayat.append(f"{text} ﴿{arabic_digits(number)}﴾")
            lines.append(" ".join(ayat))
            blocks.append("\n".join(lines))
        return "\n\n".join(blocks)


def tail_after_last_ayah(text: str) -> str:
    """ذيل الذكر بعد آخر رقم آية (مثل «بعد كل صلاة…»)."""
    index = text.rfind("﴾")
    return text[index + 1:].strip() if index >= 0 else ""


def rewrite(db: sqlite3.Connection) -> int:
    mushaf = Mushaf(db)
    changed = 0
    for dhikr_id, text, source in db.execute("SELECT id, text, source FROM dhikr").fetchall():
        new_text: str | None = None
        match = SIMPLE_SOURCE.match(source or "")
        if dhikr_id in COMPOSITE:
            ranges, prefix = COMPOSITE[dhikr_id]
            parts = [prefix] if prefix else []
            parts.append(mushaf.passage(ranges))
            tail = tail_after_last_ayah(text)
            if tail:
                parts.append(tail)
            new_text = "\n".join(parts)
        elif dhikr_id in PARTIAL:
            surah, number, start = PARTIAL[dhikr_id]
            words = mushaf.ayah(surah, number).split(" ")
            new_text = "﴿" + " ".join(words[start:]) + "﴾"
        elif match:
            surah = mushaf.surah_ids.get(plain(match.group(1)))
            if surah is None:
                raise KeyError(f"{dhikr_id}: سورة غير معروفة {match.group(1)}")
            new_text = mushaf.passage([(surah, int(match.group(2)), int(match.group(2)))])
        if new_text is not None and new_text != text:
            db.execute("UPDATE dhikr SET text = ? WHERE id = ?", (new_text, dhikr_id))
            changed += 1
    db.commit()
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()
    db = sqlite3.connect(args.db)
    try:
        changed = rewrite(db)
    finally:
        db.close()
    print(f"أُعيدت كتابة {changed} ذكراً من نص المصحف")
    return 0


if __name__ == "__main__":
    sys.exit(main())
