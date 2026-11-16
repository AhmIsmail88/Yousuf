"""استيراد كتب «التاريخ الإسلامي» إلى content.sqlite.

    python tools/content_builder/books.py --source book.json
    python tools/content_builder/finalize.py

ملف JSON:
{
  "slug": "raheeq",
  "title": "الرحيق المختوم",
  "author": "صفي الرحمن المباركفوري",
  "category": "history",
  "license": "إذن كتابي من الناشر بتاريخ …",   ← إلزامي (القيد ٩)
  "source_url": "https://…",
  "reviewed_by": "اسم المراجع",                 ← إلزامي (SPEC §4)
  "sections": [{"title": "…", "body": "…"}, …]
}

يرفض الاستيراد أي كتاب بلا ترخيص واضح أو بلا مراجع — لا يدخل التطبيق
نص بلا إذن (constraints §9، §15). إعادة الاستيراد بالـ slug نفسه تستبدل الكتاب.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.sqlite"

SCHEMA = """
CREATE TABLE IF NOT EXISTS book (
    id INTEGER PRIMARY KEY,
    slug TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    author TEXT,
    category TEXT NOT NULL DEFAULT 'history',
    license TEXT NOT NULL,
    source_url TEXT,
    reviewed_by TEXT
);
CREATE TABLE IF NOT EXISTS book_section (
    id INTEGER PRIMARY KEY,
    book_id INTEGER NOT NULL REFERENCES book(id),
    sort INTEGER NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_book_section ON book_section(book_id, sort);
"""


def ensure_schema(db: sqlite3.Connection) -> None:
    db.executescript(SCHEMA)


def main() -> int:
    parser = argparse.ArgumentParser(description="استيراد كتاب")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--source", type=Path, help="ملف JSON للكتاب")
    parser.add_argument("--schema-only", action="store_true", help="إنشاء الجداول فقط")
    args = parser.parse_args()

    db = sqlite3.connect(args.db)
    ensure_schema(db)
    if args.schema_only:
        db.commit()
        print("أُنشئت جداول الكتب.")
        return 0
    if args.source is None:
        print("حدّد --source", file=sys.stderr)
        return 2

    book = json.loads(args.source.read_text(encoding="utf-8"))
    for field in ("slug", "title", "license", "reviewed_by"):
        if not str(book.get(field) or "").strip():
            print(f"مرفوض: الحقل «{field}» إلزامي (لا نص بلا إذن ومراجعة).", file=sys.stderr)
            return 1
    sections = book.get("sections") or []
    if not sections or any(not s.get("title") or not s.get("body") for s in sections):
        print("مرفوض: كل فصل يحتاج عنواناً ونصاً.", file=sys.stderr)
        return 1

    old = db.execute("SELECT id FROM book WHERE slug = ?", (book["slug"],)).fetchone()
    if old:
        db.execute("DELETE FROM book_section WHERE book_id = ?", (old[0],))
        db.execute("DELETE FROM book WHERE id = ?", (old[0],))
    cur = db.execute(
        "INSERT INTO book (slug, title, author, category, license, source_url, reviewed_by)"
        " VALUES (?, ?, ?, ?, ?, ?, ?)",
        (
            book["slug"],
            book["title"],
            book.get("author"),
            book.get("category", "history"),
            book["license"],
            book.get("source_url"),
            book["reviewed_by"],
        ),
    )
    book_id = cur.lastrowid
    for index, section in enumerate(sections):
        db.execute(
            "INSERT INTO book_section (book_id, sort, title, body) VALUES (?, ?, ?, ?)",
            (book_id, index, section["title"].strip(), section["body"].strip()),
        )
    db.commit()
    print(f"استُورد «{book['title']}»: {len(sections)} فصلاً.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
