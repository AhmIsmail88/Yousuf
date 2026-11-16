import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/utils/arabic_dates.dart';

void main() {
  test('١ رمضان ١٤٤٥ = ١١ مارس ٢٠٢٤', () {
    final hijri = hijriDay(DateTime(2024, 3, 11));
    expect(hijri, isNotNull);
    expect(hijri!.year, 1445);
    expect(hijri.month, 9);
    expect(hijri.day, 1);
    expect(hijri.monthName, 'رمضان');
  });

  test('١ محرم ١٤٤٥ = ١٩ يوليو ٢٠٢٣', () {
    final hijri = hijriDay(DateTime(2023, 7, 19));
    expect(hijri!.year, 1445);
    expect(hijri.month, 1);
    expect(hijri.day, 1);
  });

  test('الإزاحة تعادل تحريك التاريخ الميلادي يوماً واحداً', () {
    final date = DateTime(2026, 11, 11);
    final shifted = hijriDay(date, offsetDays: 1)!;
    final nextDay = hijriDay(DateTime(2026, 11, 12))!;
    expect(shifted.year, nextDay.year);
    expect(shifted.month, nextDay.month);
    expect(shifted.day, nextDay.day);
  });

  test('الإزاحة السالبة ترجع يوماً للخلف', () {
    final date = DateTime(2026, 11, 11);
    final shifted = hijriDay(date, offsetDays: -2)!;
    final twoDaysBack = hijriDay(DateTime(2026, 11, 9))!;
    expect(shifted.month, twoDaysBack.month);
    expect(shifted.day, twoDaysBack.day);
  });

  test('الصيغة العربية تحتوي اسم الشهر ولاحقة هـ', () {
    final hijri = hijriDay(DateTime(2024, 3, 11))!;
    expect(hijri.formatted, contains('رمضان'));
    expect(hijri.formatted, endsWith('هـ'));
  });

  test('الأيام البيض ١٣–١٥ فقط', () {
    expect(const HijriDay(year: 1448, month: 5, day: 12).isWhiteDay, isFalse);
    expect(const HijriDay(year: 1448, month: 5, day: 13).isWhiteDay, isTrue);
    expect(const HijriDay(year: 1448, month: 5, day: 15).isWhiteDay, isTrue);
    expect(const HijriDay(year: 1448, month: 5, day: 16).isWhiteDay, isFalse);
  });

  test('التاريخ الميلادي بصيغة عربية', () {
    final text = formatGregorianDate(DateTime(2026, 11, 11));
    expect(text, contains('نوفمبر'));
    expect(text, contains('2026'));
    expect(text, startsWith('الأربعاء'));
  });

  test('مفتاح اليوم بصيغة yyyy-MM-dd', () {
    expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
  });
}
