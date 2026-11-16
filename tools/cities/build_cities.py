#!/usr/bin/env python3
"""يبني قاعدة المدن الأوفلاين (أكبر 10,000 مدينة) من GeoNames.

المصدر: https://download.geonames.org/export/dump/cities15000.zip
الترخيص: CC BY 4.0 — يجب الإسناد إلى GeoNames في شاشة «المصادر» (SEE README).

الاستخدام (من مجلد yousuf/):
    python tools/cities/build_cities.py
"""

import io
import json
import os
import sys
import urllib.request
import zipfile

SOURCE_URL = "https://download.geonames.org/export/dump/cities15000.zip"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(HERE, ".cache")
CACHE_ZIP = os.path.join(CACHE_DIR, "cities15000.zip")
OUT_PATH = os.path.join(HERE, "..", "..", "assets", "db", "cities.json")
TOP_N = 10000

# أعمدة cities15000.txt (بلا ترويسة، مفصولة بـ Tab):
# 0 geonameid · 1 name · 2 asciiname · 3 alternatenames · 4 lat · 5 lng
# 6 feature class · 7 feature code · 8 country code · 9 cc2 · 10..13 admin1..4
# 14 population · 15 elevation · 16 dem · 17 timezone · 18 modification date
COL_GEONAMEID = 0
COL_NAME = 1
COL_ASCII = 2
COL_ALT = 3
COL_LAT = 4
COL_LNG = 5
COL_COUNTRY = 8
COL_POP = 14
COL_TZ = 17

# دول عربية تُقدَّم في ترتيب القائمة الافتراضية (ثم الباقي بالسكان).
ARAB_COUNTRIES = {
    "SA", "EG", "AE", "QA", "KW", "BH", "OM", "YE", "JO", "LB", "SY",
    "IQ", "PS", "SD", "LY", "TN", "DZ", "MA", "MR", "SO", "DJ", "KM",
}


def is_arabic_letter(ch: str) -> bool:
    return "\u0600" <= ch <= "\u06ff"


def is_pure_arabic(name: str) -> bool:
    """اسم عربي خالص: ≥90% من حروفه عربية ولا يحتوي لاتينياً.

    GeoNames يخلط أحياناً أسماء عربية بحروف لاتينية في نفس المدخل،
    فنرفض أي اسم مختلط بدل عرضه مشوّشاً.
    """
    letters = [ch for ch in name if ch.isalpha()]
    if len(letters) < 2:
        return False
    arabic = sum(1 for ch in letters if is_arabic_letter(ch))
    return arabic / len(letters) >= 0.9


# حروف عربية فصحى فقط (بدون حروف أويغورية/أردية/فارسية).
ARABIC_LETTERS = set(
    "ءآأؤإئابةتثجحخدذرزسشصضطظعغفقكلمنهويى"
    "ًٌٍَُِّْٰـ"
)


def is_standard_arabic(name: str) -> bool:
    """اسم بحروف عربية فصحى فقط (≥ حرفين) — لا لاتيني ولا أويغوري/أردي."""
    letters = [ch for ch in name if ch.isalpha()]
    if len(letters) < 2:
        return False
    return all(ch in ARABIC_LETTERS for ch in letters)


def arabic_name_key(name: str) -> tuple[int, int]:
    """مفتاح اختيار: «ال» التعريف أولاً، ثم الأقصر (الاسم الأكثر شيوعاً)."""
    return (1 if name.startswith("ال") else 0, -len(name))


def pick_arabic_name(alternatenames: str, fallback: str) -> str:
    """أفضل اسم عربي فصيح في الأسماء البديلة، وإلا الاسم اللاتيني."""
    best = fallback
    best_key: tuple[int, int] | None = None
    for name in alternatenames.split(","):
        candidate = name.strip()
        if not candidate or not is_standard_arabic(candidate):
            continue
        key = arabic_name_key(candidate)
        if best_key is None or key > best_key:
            best_key = key
            best = candidate
    return best


def load_rows() -> list[list[str]]:
    os.makedirs(CACHE_DIR, exist_ok=True)
    if not os.path.exists(CACHE_ZIP):
        print("تنزيل:", SOURCE_URL)
        urllib.request.urlretrieve(SOURCE_URL, CACHE_ZIP)
    with zipfile.ZipFile(CACHE_ZIP) as archive:
        with archive.open("cities15000.txt") as raw:
            rows = []
            for line in io.TextIOWrapper(raw, encoding="utf-8"):
                cols = line.rstrip("\n").split("\t")
                if len(cols) <= COL_TZ:
                    continue
                rows.append(cols)
    return rows


def main() -> int:
    rows = load_rows()
    print(f"إجمالي المدن في المصدر: {len(rows)}")

    def population(cols: list[str]) -> int:
        try:
            return int(cols[COL_POP] or 0)
        except ValueError:
            return 0

    rows.sort(key=population, reverse=True)
    # الأسماء العربية أولاً ثم الباقي حسب السكان — قاعدة عربية/إسلامية.
    top = sorted(
        rows[: TOP_N * 3],
        key=lambda cols: (
            0 if cols[COL_COUNTRY] in ARAB_COUNTRIES else 1,
            -population(cols),
        ),
    )[:TOP_N]

    cities = []
    arabic_count = 0
    for cols in top:
        arabic = pick_arabic_name(cols[COL_ALT], cols[COL_NAME])
        if is_pure_arabic(arabic):
            arabic_count += 1
        cities.append(
            {
                "id": int(cols[COL_GEONAMEID]),
                "ar": arabic,
                "en": cols[COL_ASCII] or cols[COL_NAME],
                "cc": cols[COL_COUNTRY],
                "lat": round(float(cols[COL_LAT]), 5),
                "lng": round(float(cols[COL_LNG]), 5),
                "tz": cols[COL_TZ],
                "pop": population(cols),
            }
        )

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as out:
        json.dump(cities, out, ensure_ascii=False, separators=(",", ":"))

    size = os.path.getsize(OUT_PATH)
    print(f"كُتب: {os.path.normpath(OUT_PATH)}")
    print(f"عدد المدن: {len(cities)} · الحجم: {size:,} بايت")
    print(f"تغطية الاسم العربي: {arabic_count}/{len(cities)}")

    # ---- فحوصات القبول ----
    failures = []
    if len(cities) != TOP_N:
        failures.append(f"العدد {len(cities)} != {TOP_N}")

    by_id = {city["id"]: city for city in cities}
    for expected_id, expected_ar, label in (
        (108410, "الرياض", "الرياض"),
        (360630, "القاهرة", "القاهرة"),
        (2950159, "برلين", "برلين"),
        (5128581, "نيويورك", "نيويورك"),
        (745044, "إسطنبول", "إسطنبول"),
    ):
        city = by_id.get(expected_id)
        if city is None:
            failures.append(f"{label} غير موجودة")
        elif not is_pure_arabic(city["ar"]):
            failures.append(f"{label}: اسم عربي غير سليم ({city['ar']})")

    # لا اسم عربي مشوّش (يحتوي حرفاً لاتينياً) في أي مدينة لها اسم عربي.
    mixed = [
        city["ar"]
        for city in cities
        if any(ch.isascii() and ch.isalpha() for ch in city["ar"])
        and sum(1 for ch in city["ar"] if is_arabic_letter(ch)) >= 2
    ]
    if mixed:
        failures.append(f"أسماء عربية مختلطة: {len(mixed)} مثال: {mixed[:3]}")

    with open(OUT_PATH, encoding="utf-8") as f:
        loaded = json.load(f)
    if len(loaded) != len(cities):
        failures.append("JSON غير متسق بعد إعادة القراءة")

    if failures:
        print("فشل الفحص:", "; ".join(failures))
        return 1
    print("كل فحوصات القبول ناجحة ✓")
    return 0


if __name__ == "__main__":
    sys.exit(main())
