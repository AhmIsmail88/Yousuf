#!/usr/bin/env python3
"""التفاسير والترجمات وأسباب النزول — من حزمة `D:/coding/Quran` (quran-tafsir.sqlite).

    # ١) التفسير الميسر وأسباب النزول (الواحدي) داخل content.sqlite
    python tools/content_builder/quran_extras.py bundle
    python tools/content_builder/finalize.py

    # ٢) ابن كثير والطبري والترجمات الحرة: ملف SQLite مضغوط لكل مصدر + catalog.json
    python tools/content_builder/quran_extras.py extras --out out/quran_extras

المصادر وتراخيصها (LICENSES.md في الحزمة):
- التفسير الميسر، أسباب النزول (الواحدي، آية بآية)، ابن كثير، الطبري: مخازن
  Quranpedia.net (إصدار المخزن في جدول meta) — استخدام حر داخل التطبيقات، وإعادة
  النشر كملفات تُنزَّل تشترط ذكر Quranpedia.net ورابطه وإصدار المخزن. المتون
  التراثية ملك عام.
- الترجمات: Pickthall (ت 1936)، Elmalılı Hamdi Yazır (ت 1942)، محمد جوناگڑھی
  (ت 1941) — ملك عام. **لا تُضمَّن** الترجمات المحمية (Saheeh International،
  Diyanet، جالندھری) ولا أسباب النزول الإنجليزية (حقوقها غير معلنة).
النصوص تُنسخ حرفياً. ``reviewed_by`` قيد المراجعة الشرعية.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.sqlite"
DEFAULT_SOURCE = Path("D:/coding/Quran/quran-tafsir.sqlite")
FORMAT_VERSION = 1

# المصادر القابلة للتنزيل: (المعرّف، النوع، المعرّف في الحزمة، الاسم العربي، الاسم الإنجليزي، اللغة، المؤلف)
EXTRAS = [
    ("ibn_kathir", "tafsir", "ibn_kathir", "تفسير ابن كثير", "Tafsir Ibn Kathir", "ar",
     "إسماعيل بن عمر بن كثير (ت ٧٧٤هـ)"),
    ("tabari", "tafsir", "tabari", "جامع البيان — تفسير الطبري", "Tafsir al-Tabari", "ar",
     "محمد بن جرير الطبري (ت ٣١٠هـ)"),
    ("en_pickthall", "translation", 19, "الإنجليزية — Pickthall", "English — Pickthall", "en",
     "Marmaduke Pickthall (d. 1936)"),
    ("tr_elmalili", "translation", 52, "التركية — Elmalılı Hamdi Yazır", "Turkish — Elmalılı Hamdi Yazır",
     "tr", "Elmalılı Hamdi Yazır (ö. 1942)"),
    ("ur_junagarhi", "translation", 54, "الأردية — محمد جوناگڑھی", "Urdu — Muhammad Junagarhi", "ur",
     "محمد جوناگڑھی (1941)"),
]

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE body (id INTEGER PRIMARY KEY, text TEXT NOT NULL);
-- مفتاح الآية = السورة × ١٠٠٠ + رقم الآية. التفسير المشترك بين آيات يُخزَّن مرة.
CREATE TABLE ayah (ayah_key INTEGER PRIMARY KEY, body_id INTEGER NOT NULL);
"""


def source_meta(src: sqlite3.Connection) -> dict[str, str]:
    return dict(src.execute("SELECT key, value FROM meta").fetchall())


# ---------------- ١) المضمَّن ----------------

def bundle(db_path: Path, source: Path) -> None:
    src = sqlite3.connect(source)
    db = sqlite3.connect(db_path)
    ayah_ids = {(s, n): i for i, s, n in db.execute("SELECT id, surah_id, number FROM ayah")}

    db.execute(
        "INSERT INTO tafsir (slug, name, author, bundled) VALUES (?, ?, ?, 1)"
        " ON CONFLICT(slug) DO UPDATE SET name = excluded.name, author = excluded.author,"
        " bundled = 1",
        ("muyassar", "التفسير الميسر", "نخبة من العلماء — مجمع الملك فهد لطباعة المصحف الشريف"),
    )
    tafsir_id = db.execute("SELECT id FROM tafsir WHERE slug = 'muyassar'").fetchone()[0]
    db.execute("DELETE FROM tafsir_text WHERE tafsir_id = ?", (tafsir_id,))
    rows = src.execute(
        "SELECT sura, aya, text FROM tafsir WHERE tafsir_id = 'muyassar'"
    ).fetchall()
    for sura, aya, text in rows:
        db.execute(
            "INSERT INTO tafsir_text (tafsir_id, ayah_id, text) VALUES (?, ?, ?)",
            (tafsir_id, ayah_ids[(sura, aya)], text.strip()),
        )

    db.executescript(
        """
        DROP TABLE IF EXISTS asbab_nuzul;
        CREATE TABLE asbab_nuzul (
            ayah_id INTEGER PRIMARY KEY REFERENCES ayah(id),
            text TEXT NOT NULL
        );
        """
    )
    asbab = src.execute("SELECT sura, aya, text FROM asbab_nuzul_ar").fetchall()
    for sura, aya, text in asbab:
        db.execute(
            "INSERT INTO asbab_nuzul (ayah_id, text) VALUES (?, ?)",
            (ayah_ids[(sura, aya)], text.strip()),
        )
    db.commit()
    db.close()
    meta = source_meta(src)
    print(f"التفسير الميسر: {len(rows)} آية · أسباب النزول: {len(asbab)} آية"
          f" · Quranpedia {meta.get('quranpedia_dump_version')}")


# ---------------- ٢) القابل للتنزيل ----------------

def build_extra(src: sqlite3.Connection, spec: tuple, out: Path, meta: dict) -> dict:
    slug, kind, key, name_ar, name_en, lang, author = spec
    if kind == "tafsir":
        rows = src.execute(
            "SELECT sura, aya, text FROM tafsir WHERE tafsir_id = ? ORDER BY sura, aya", (key,)
        ).fetchall()
        source = meta.get("tafsir_source_note", "")
    else:
        rows = src.execute(
            "SELECT sura, aya, text FROM translation WHERE translation_id = ? ORDER BY sura, aya",
            (key,),
        ).fetchall()
        source = meta.get("translations_source", "")
    if len(rows) != 6236:
        raise SystemExit(f"{slug}: {len(rows)} بدل 6236")

    path = out / f"{slug}.sqlite"
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    bodies: dict[str, int] = {}
    for sura, aya, text in rows:
        text = text.strip()
        body_id = bodies.get(text)
        if body_id is None:
            body_id = len(bodies) + 1
            bodies[text] = body_id
            db.execute("INSERT INTO body VALUES (?, ?)", (body_id, text))
        db.execute("INSERT INTO ayah VALUES (?, ?)", (sura * 1000 + aya, body_id))
    for k, v in {
        "slug": slug, "kind": kind, "name_ar": name_ar, "name_en": name_en,
        "language": lang, "author": author, "format": str(FORMAT_VERSION),
        "source": source,
        "quranpedia_dump_version": meta.get("quranpedia_dump_version", ""),
    }.items():
        db.execute("INSERT INTO meta VALUES (?, ?)", (k, v))
    db.commit()
    db.execute("VACUUM")
    db.close()

    gz = out / f"{slug}.sqlite.gz"
    with path.open("rb") as raw, gz.open("wb") as target, gzip.GzipFile(
        filename="", mode="wb", fileobj=target, compresslevel=9, mtime=0
    ) as packed:
        packed.write(raw.read())
    entry = {
        "slug": slug, "kind": kind, "name_ar": name_ar, "name_en": name_en,
        "language": lang, "author": author, "file": gz.name,
        "bytes": gz.stat().st_size, "sqlite_bytes": path.stat().st_size,
        "sha256": hashlib.sha256(gz.read_bytes()).hexdigest(),
        "texts": len(bodies),
    }
    print(f"{name_ar}: {len(bodies)} نصاً لـ ٦٢٣٦ آية · {entry['bytes'] // 1024} ك.ب مضغوطاً")
    return entry


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["bundle", "extras"])
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--out", type=Path,
                        default=Path(__file__).resolve().parent / "out" / "quran_extras")
    args = parser.parse_args()
    if not args.source.exists():
        raise SystemExit(f"المصدر غير موجود: {args.source}")
    if args.command == "bundle":
        bundle(args.db, args.source)
        return 0
    src = sqlite3.connect(args.source)
    meta = source_meta(src)
    args.out.mkdir(parents=True, exist_ok=True)
    catalog = [build_extra(src, spec, args.out, meta) for spec in EXTRAS]
    (args.out / "catalog.json").write_text(
        json.dumps({"format": FORMAT_VERSION,
                    "quranpedia_dump_version": meta.get("quranpedia_dump_version"),
                    "extras": catalog}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print("catalog.json ←", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
