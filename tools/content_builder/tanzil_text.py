"""نص المصحف العثماني من Tanzil (الإصدار الرسمي 1.1) — حرفاً بحرف.

يُرسم بخط مجمع الملك فهد بالنسخة التي يستعملها Tanzil (hafs.otf، الإصدار
1.001)، فيظهر كما في موقع Tanzil: التطويل قبل الألف الخنجرية («أُو۟لَـٰٓئِكَ»)
يحمل الألف والمدّ في مكانهما.

المصدر: ``sources/tanzil/quran-uthmani.sql`` — نسخة حرفية من
https://tanzil.net/download/ (فيها التطويل قبل الألف الخنجرية «ٱلرَّحْمَـٰنِ»
الذي يحتاجه الرسم الصحيح؛ نسخ الوسطاء تحذفه). الترخيص في الملف نفسه:
CC BY 3.0، يُمنع تغيير النص. البسملة ملحقة بأول كل سورة كما في المصدر.

    python tools/content_builder/tanzil_text.py
    python tools/content_builder/quran_adhkar.py
    python tools/content_builder/finalize.py
"""

from __future__ import annotations

import argparse
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.sqlite"
SOURCE = Path(__file__).resolve().parent / "sources" / "tanzil" / "quran-uthmani.sql"

ROW = re.compile(r"\((\d+), (\d+), (\d+), '((?:[^'\\]|\\.)*)'\)")


def load() -> dict[tuple[int, int], str]:
    sql = SOURCE.read_text(encoding="utf-8")
    texts = {}
    for _, sura, aya, text in ROW.findall(sql):
        texts[(int(sura), int(aya))] = re.sub(r"\\(.)", r"\1", text)
    if len(texts) != 6236:
        raise SystemExit(f"عدد الآيات غير صحيح: {len(texts)}")
    return texts


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()
    texts = load()
    db = sqlite3.connect(args.db)
    try:
        rows = db.execute("SELECT id, surah_id, number FROM ayah").fetchall()
        if len(rows) != len(texts):
            raise SystemExit("عدد آيات قاعدة البيانات لا يطابق المصدر")
        for ayah_id, sura, aya in rows:
            db.execute(
                "UPDATE ayah SET text_uthmani = ? WHERE id = ?",
                (texts[(sura, aya)], ayah_id),
            )
        db.commit()
    finally:
        db.close()
    print(f"كُتب نص Tanzil الرسمي لـ {len(rows)} آية")
    return 0


if __name__ == "__main__":
    sys.exit(main())
