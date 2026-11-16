import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/utils/arabic_digits.dart';
import 'package:yousuf/core/utils/time_format.dart';

void main() {
  test('تحويل 24 ساعة إلى 12 ساعة', () {
    expect(TimeFormat.to12h('17:09', hindiDigits: false), '5:09 م');
    expect(TimeFormat.to12h('04:46', hindiDigits: false), '4:46 ص');
    expect(TimeFormat.to12h('00:05', hindiDigits: false), '12:05 ص');
    expect(TimeFormat.to12h('12:00', hindiDigits: false), '12:00 م');
  });

  test('الأرقام الهندية والعربية', () {
    expect(toHindiDigits('123'), '١٢٣');
    expect(toArabicDigits('١٢٣'), '123');
    expect(TimeFormat.to12h('17:09'), '٥:٠٩ م');
    expect(TimeFormat.digits('17:09', hindi: false), '17:09');
  });

  test('دقائق اليوم والفرق بين وقتين', () {
    expect(TimeFormat.minutesOfDay('00:00'), 0);
    expect(TimeFormat.minutesOfDay('17:09'), 1029);
    expect(TimeFormat.minutesBetween('17:09', '18:39'), 90);
    expect(TimeFormat.minutesBetween('18:39', '17:09'), -90);
  });
}
