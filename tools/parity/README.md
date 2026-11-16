# مرجع تطابق المواقيت (Dart ↔ Kotlin)

الغرض: ضمان أن حساب Dart (لل عرض) وحساب Kotlin (للجدولة) يعطيان **نفس النتيجة
بالدقيقة** — شرط SPEC §11 (50 مدينة × 365 يوماً × 6 مواقيت، فرق = 0).

## الملفات

| الملف | الوصف |
| --- | --- |
| `cities.json` | 50 مدينة موزعة على القارات، لكل مدينة طريقة حساب ومذهب |
| `bin/generate_reference.dart` | مولّد الملف المرجعي من كود Dart (مصدر الحقيقة للعرض) |
| `reference_times.json` | الملف المولّد — يقرأه اختبار Kotlin ويقارن به |

## التوليد

من مجلد `yousuf/`:

```powershell
dart run tools/parity/bin/generate_reference.dart            # 2026-11-01 + 30 يوماً
dart run tools/parity/bin/generate_reference.dart 2026-01-01 365
```

## الاستهلاك

- **Kotlin:** `android/app/src/test/kotlin/app/yousuf/adhan/PrayerCalcParityTest.kt`
  يقرأ `tools/parity/reference_times.json` ويقارن كل مدخل بالدقيقة.
- **CI:** شغّل التوليد بمدى 365 يوماً قبل اختبارات gradle في الإصدار النهائي.

## ملاحظات

- الملف المرجعي يُرحَّل داخل المستودع (حجمه ~165KB لمدى 30 يوماً).
- أي تغيير في كود حساب Dart يستلزم إعادة التوليد وتشغيل اختبار التطابق.
