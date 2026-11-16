# خط إنتاج المحتوى — content.sqlite

يبني قاعدة محتوى القرآن (قراءة فقط) التي تُشحن مع التطبيق، ويحفظ بصمات
المصادر لضمان سلامة النص (SPEC §4، §5).

## المصادر والتراخيص

| المحتوى | المصدر الفعلي | الترخيص |
| --- | --- | --- |
| النص العثماني | alquran.cloud — `quran-uthmani` (نص Tanzil) | CC BY 3.0 — نسخ حرفي، بلا تعديل، مع ذكر المصدر |
| النص الإملائي | alquran.cloud — `quran-simple` | نفسه (نص Tanzil) |
| بيانات السور والآيات (page/juz/hizb/sajda) | من نفس الاستجابتين | نفسه |

> موقع Tanzil الرسمي قد يطلب تنزيلاً تفاعلياً؛ alquran.cloud يقدّم نص Tanzil
> نفسه. عند توفر تنزيل مباشر من Tanzil يُستبدل المصدر ويُعاد توليد البصمات.

## الاستخدام

من مجلد `yousuf/`:

```powershell
python tools/content_builder/build.py     # ينزّل مرة واحدة إلى out/raw/ ثم يبني
python tools/content_builder/verify.py   # فحص 114 سورة / 6236 آية / البصمات
python tools/content_builder/adhkar.py --hisn --seed-quranic  # حصن المسلم + أدعية القرآن
python tools/content_builder/adhkar.py --export-csv docs/adhkar-review.csv
python tools/content_builder/adhkar.py --mark-reviewed "الشيخ إسلام"
python tools/content_builder/adhkar.py --source adhkar_reviewed.json
```

## الأذكار — بوابة المراجعة الشرعية

`dhikr_category` و`dhikr` تبقى فارغة في `build.py` لأن SPEC §4 يمنع شحن أي
نص قبل توقيع المراجع. `adhkar.py` هو المسار الوحيد لإدخالها:

- `--hisn` يستورد متن «حصن المسلم» (١٣٢ باباً) من نسخة MIT مع التخريج،
  ويأخذ عدد التكرار من واجهة hisnmuslim.com بمطابقة النص.
- `--seed-quranic` ينشئ «أدعية من القرآن» بنسخ نص الآيات حرفياً من جدول `ayah`
  (نفس نص Tanzil المشحون) ومصدرها اسم السورة ورقم الآية — بلا تحرير.
- `--export-csv` يصدّر كل الأذكار لمراجعة خارجية (Excel).
- `--mark-reviewed` يوقّع المحتوى باسم المراجع في `content_version.reviewed_by`
  فيختفي تنبيه «قيد المراجعة» من التطبيق.
- `--source` يقرأ ملفاً يوقّعه المراجع ويستبدل أقسامه، ويرفض أي ذكر بلا
  نص أو مصدر أو بتكرار غير صالح.
- أي إعادة استيراد تُصفّر التوقيع (لأن المحتوى تغيّر) — وهذا مقصود.

التفاصيل والحصيلة في `docs/ADHKAR.md`.

المخرجات (كلها في `out/` — خارج المستودع):

- `content.sqlite` — الجداول الـ14 كاملة من SPEC §5 (الفارغ يبقى فارغاً).
- `raw/*.json` — نسخ المصادر الخام (تُحفظ للبصمات).
- `sources_checksums.json` — sha256 لكل مصدر.

## TODO قبل النشر

1. التفسير الميسر (`tafsir` + `tafsir_text`) من QUL بعد التحقق من الترخيص.
2. `page_line` من QUL Mushaf Layout (604 صفحة × 15 سطراً).
3. الحديث (الكتب الستة + الموطأ) من `fawazahmed0/hadith-api` (Unlicense) مع الدرجات.
4. ملف الأذكار المُراجَع (تسعة أقسام) عبر `adhkar.py --source` بعد توقيع الشيخ إسلام.
5. أسماء الله الحسنى والمناسبات الهجرية.
6. `content_version.reviewed_by` يُملأ بتوقيع المراجع الشرعي، و`version` يُرقّى.
7. تسجيل مصدر Tanzil ورابطه داخل شاشة «المصادر» في التطبيق (شرط الترخيص) — منفّذ في `settings_screen.dart`.
