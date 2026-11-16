import 'package:flutter/material.dart';

import 'package:yousuf/core/l10n/tr.dart';
import 'package:flutter/services.dart';

import 'package:yousuf/core/platform/adhan_channel.dart';

/// شريط يظهر أعلى التطبيق أثناء تشغيل الأذان، مع زر إيقاف فوري.
///
/// يوضع في `MaterialApp.builder` ليطابق كل الشاشات (بما فيها المسارات
/// المفتوحة فوق التبويبات مثل الإعدادات والمصحف).
class AdhanPlayingBar extends StatelessWidget {
  const AdhanPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 8, 6),
          child: Row(
            children: [
              Icon(Icons.volume_up, size: 18, color: scheme.onPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('الأذان يُشغَّل الآن', 'Adhan is playing'),
                  style: TextStyle(color: scheme.onPrimary, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await AdhanChannel().stopAdhan();
                  HapticFeedback.mediumImpact();
                },
                style: TextButton.styleFrom(foregroundColor: scheme.onPrimary),
                child: Text(context.tr('إيقاف', 'Stop')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
