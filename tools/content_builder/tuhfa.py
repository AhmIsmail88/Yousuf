#!/usr/bin/env python3
"""تحفة الأطفال والغلمان (الجمزوري) — النص داخل التطبيق، والصوت للتنزيل.

    python tools/content_builder/tuhfa.py           # النص ← content.sqlite
    python tools/content_builder/finalize.py
    python tools/content_builder/tuhfa.py --audio D:/coding/asr-work/hf_kids/tuhfa

المصدر: حزمة D:/coding/Quran/tuhfat-al-atfal.
- المتن (٦١ بيتاً): ملك عام؛ النص من ويكي مصدر (CC BY-SA) — يُذكر المصدر.
- الصوت: محمد عبد الرحمن الحوفي، archive.org (elhoofy_20180714_2134) بعلامة
  Public Domain Mark من الرافع. يُذكر القارئ والمصدر.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.sqlite"
SOURCE = Path("D:/coding/Quran/tuhfat-al-atfal")


def import_text(db_path: Path) -> None:
    src = sqlite3.connect(SOURCE / "tuhfat-al-atfal.sqlite")
    db = sqlite3.connect(db_path)
    db.executescript(
        """
        DROP TABLE IF EXISTS tuhfa_section;
        DROP TABLE IF EXISTS tuhfa_verse;
        CREATE TABLE tuhfa_section (id INTEGER PRIMARY KEY, title TEXT NOT NULL);
        CREATE TABLE tuhfa_verse (
            number INTEGER PRIMARY KEY,
            section_id INTEGER NOT NULL REFERENCES tuhfa_section(id),
            line1 TEXT NOT NULL,
            line2 TEXT NOT NULL
        );
        """
    )
    sections = src.execute("SELECT id, title FROM sections ORDER BY id").fetchall()
    verses = src.execute(
        "SELECT number, section_id, line1, line2 FROM verses ORDER BY number"
    ).fetchall()
    if len(verses) != 61:
        raise SystemExit(f"عدد الأبيات {len(verses)} بدل 61")
    db.executemany("INSERT INTO tuhfa_section VALUES (?, ?)", sections)
    db.executemany(
        "INSERT INTO tuhfa_verse VALUES (?, ?, ?, ?)",
        [(n, s, a.strip(), b.strip()) for n, s, a, b in verses],
    )
    db.commit()
    db.close()
    print(f"تحفة الأطفال: {len(sections)} أبواب · {len(verses)} بيتاً")


def export_audio(out: Path) -> None:
    """ملف لكل باب باسم لاتيني (01.mp3…) + المتن كاملاً (full.mp3) + فهرس."""
    src = sqlite3.connect(SOURCE / "tuhfat-al-atfal.sqlite")
    out.mkdir(parents=True, exist_ok=True)
    entries = []
    for _, section_id, title, file, duration in src.execute(
        "SELECT id, section_id, title, file, duration_sec FROM audio ORDER BY id"
    ):
        name = "full.mp3" if section_id is None else f"{section_id:02d}.mp3"
        target = out / name
        shutil.copyfile(SOURCE / file, target)
        data = target.read_bytes()
        entries.append({
            "section": section_id, "title": title, "file": name,
            "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "duration_sec": duration,
        })
    (out / "tuhfa_audio.json").write_text(
        json.dumps(entries, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"صوت التحفة: {len(entries)} ملفاً ← {out}")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--audio", type=Path, help="مجلد تصدير ملفات الصوت")
    args = parser.parse_args()
    if args.audio:
        export_audio(args.audio)
    else:
        import_text(args.db)
    return 0


if __name__ == "__main__":
    sys.exit(main())
