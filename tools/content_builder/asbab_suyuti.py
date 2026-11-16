#!/usr/bin/env python3
"""«لباب النقول في أسباب النزول» للسيوطي — مربوطاً بالآيات، ملفاً للتنزيل.

    python tools/content_builder/asbab_suyuti.py --out out/quran_extras

المصدر: islamic-library.sqlite (المكتبة الشاملة 2247). المتن ملك عام.

الكتاب مقسَّم بالسور، وكل رواية تبدأ بـ«قوله تعالى» ثم أول كلمات الآية بلا رقم
غالباً. نربط الرواية بآيتها بمطابقة تلك الكلمات (بلا تشكيل) مع آيات السورة نفسها،
مبتدئين من آخر آية رُبطت (الروايات على ترتيب المصحف). النص يُنسخ حرفياً؛
ما لا يُربط بثقة يُبلَّغ عنه ولا يُخمَّن.

الصيغة نفسها لملفات التفاسير (quran_extras.py): body(id, text) و
ayah(ayah_key = سورة×١٠٠٠+آية، body_id).
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

ROOT = Path(__file__).resolve().parents[2]
CONTENT_DB = ROOT / "assets" / "db" / "content.sqlite"
SOURCE = Path("D:/coding/Quran/islamic-library.sqlite")

DIACRITICS = re.compile("[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]")
LETTERS = str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي",
                         "ئ": "ي", "ؤ": "و", "ة": "ه", "ء": None})
NON_ARABIC = re.compile(r"[^\u0621-\u064A\s]")
ENTRY = re.compile(r"قوله\s+تعال[ىي]")
QUOTE_END = re.compile(
    r"\s(?:الآية|الآيتين|الآيات|الاية|إلى قوله|أخرج|روى|وأخرج|\(ك\)|ك\s)"
)
ALIASES = {"براءة": 9, "التوبة": 9, "الاسراء": 17, "ابراهيم": 14, "الانسان": 76,
           "الدهر": 76, "المجادلة": 58, "المجادله": 58, "الممتحنة": 60,
           "حم السجدة": 41, "ألم نشرح لك": 94, "المعوذتين": 113, "ن": 68}


def norm(text: str) -> str:
    text = DIACRITICS.sub("", text).translate(LETTERS)
    text = NON_ARABIC.sub(" ", text)
    return re.sub(r"\s+", " ", text).strip()


def surah_index(content: sqlite3.Connection) -> dict[str, int]:
    index = {}
    for sid, name in content.execute("SELECT id, name_ar FROM surah"):
        index[norm(name).removeprefix("سوره ").strip()] = sid
    for k, v in ALIASES.items():
        index[norm(k)] = v
    return index


def ayat_words(content: sqlite3.Connection) -> dict[int, list[list[str]]]:
    out: dict[int, list[list[str]]] = {}
    for sid, num, text in content.execute(
        "SELECT surah_id, number, text_simple FROM ayah ORDER BY surah_id, number"
    ):
        out.setdefault(sid, []).append(norm(text).split())
    return out


def contains(words: list[str], seq: list[str]) -> bool:
    n = len(seq)
    return any(words[i:i + n] == seq for i in range(len(words) - n + 1))


def locate(quote: list[str], ayat: list[list[str]], start: int) -> int | None:
    """أطول بادئة من نص الرواية توجد في آية واحدة؛ الأقرب بعد [start].

    المقارنة بلا مسافات: المصحف يصل كلمات يفصلها الكتاب («أولما»/«أو لما»).
    كلمة واحدة تُقبل فقط إن وُجدت خلال ثلاثين آية بعد آخر آية رُبطت.
    """
    joined = ["".join(words) for words in ayat]
    for size in range(min(7, len(quote)), 1, -1):
        seq = "".join(quote[:size])
        if len(seq) < 6:
            continue
        order = list(range(start, len(ayat))) + list(range(0, start))
        for i in order:
            if seq in joined[i]:
                return i
    if quote and len(quote[0]) >= 4:
        for i in range(start, min(start + 30, len(ayat))):
            if quote[0] in ayat[i]:
                return i
    return None


def build(out: Path) -> dict:
    content = sqlite3.connect(CONTENT_DB)
    names = surah_index(content)
    words = ayat_words(content)
    src = sqlite3.connect(SOURCE)
    pages = src.execute(
        "SELECT title, text FROM book_pages WHERE book_id = 'asbab_suyuti' ORDER BY page_id"
    ).fetchall()

    by_surah: dict[int, str] = {}
    unknown = set()
    for title, text in pages:
        key = norm(title or "").removeprefix("سوره ").strip()
        sid = names.get(key) or names.get(norm(re.sub(r"[()]", "", key)))
        if sid is None:
            unknown.add(title)
            continue
        by_surah[sid] = by_surah.get(sid, "") + " " + text

    entries: dict[int, list[str]] = {}
    linked = missed = 0
    misses = []
    for sid, text in sorted(by_surah.items()):
        parts = ENTRY.split(text)
        cursor = 0
        for part in parts[1:]:
            body = "قوله تعالى" + part.rstrip()
            head = QUOTE_END.split(" " + part.strip(), maxsplit=1)[0]
            quote = norm(head).split()
            numbers = [int("".join(str("٠١٢٣٤٥٦٧٨٩".index(d)) for d in m))
                       for m in re.findall(r"\[([٠-٩]+)\]", part[:200])]
            index = None
            if numbers and 1 <= numbers[0] <= len(words[sid]):
                index = numbers[0] - 1
            target = sid
            if index is None and quote:
                index = locate(quote, words[sid], cursor)
            # صفحة تبدأ بالسورة التالية قد تحمل آخر روايات السورة السابقة.
            if index is None and quote and sid > 1:
                prev = words[sid - 1]
                index = locate(quote, prev, max(0, len(prev) - 40))
                if index is not None:
                    target = sid - 1
            if index is None:
                missed += 1
                misses.append((sid, " ".join(quote[:6])))
                continue
            if target == sid:
                cursor = index
            entries.setdefault(target * 1000 + index + 1, []).append(body.strip())
            linked += 1

    path = out / "asbab_suyuti.sqlite"
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE body (id INTEGER PRIMARY KEY, text TEXT NOT NULL);
        CREATE TABLE ayah (ayah_key INTEGER PRIMARY KEY, body_id INTEGER NOT NULL);
    """)
    for i, (key, texts) in enumerate(sorted(entries.items()), start=1):
        db.execute("INSERT INTO body VALUES (?, ?)", (i, "\n\n".join(texts)))
        db.execute("INSERT INTO ayah VALUES (?, ?)", (key, i))
    for k, v in {
        "slug": "asbab_suyuti", "kind": "asbab", "name_ar": "لباب النقول — للسيوطي",
        "name_en": "Lubab al-Nuqul — al-Suyuti", "language": "ar",
        "author": "جلال الدين السيوطي (ت ٩١١هـ)", "format": "1",
        "source": "المكتبة الشاملة 2247 — ربط الروايات بالآيات آلياً",
    }.items():
        db.execute("INSERT INTO meta VALUES (?, ?)", (k, v))
    db.commit()
    db.execute("VACUUM")
    db.close()

    gz = out / "asbab_suyuti.sqlite.gz"
    with path.open("rb") as raw, gz.open("wb") as target, gzip.GzipFile(
        filename="", mode="wb", fileobj=target, compresslevel=9, mtime=0
    ) as packed:
        packed.write(raw.read())
    print(f"لباب النقول: {linked} رواية رُبطت بـ{len(entries)} آية · لم تُربط {missed}"
          f" · سور غير معروفة: {sorted(unknown)}")
    for sid, q in misses[:15]:
        print("   لم تُربط:", sid, q)
    return {
        "slug": "asbab_suyuti", "kind": "asbab", "name_ar": "لباب النقول — للسيوطي",
        "name_en": "Lubab al-Nuqul — al-Suyuti", "language": "ar",
        "author": "جلال الدين السيوطي (ت ٩١١هـ)", "file": gz.name,
        "bytes": gz.stat().st_size,
        "sha256": hashlib.sha256(gz.read_bytes()).hexdigest(),
        "texts": len(entries), "linked": linked, "missed": missed,
    }


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path,
                        default=Path(__file__).resolve().parent / "out" / "quran_extras")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    entry = build(args.out)
    (args.out / "asbab_suyuti.json").write_text(
        json.dumps(entry, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
