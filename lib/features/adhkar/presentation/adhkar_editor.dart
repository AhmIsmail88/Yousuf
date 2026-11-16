import 'package:flutter/material.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';

import '../domain/user_dhikr.dart';

/// حوار إضافة/تعديل ذكر شخصي.
///
/// يعيد [UserDhikr] جديداً عند الإضافة، أو نسخة معدّلة عند التعديل،
/// و`null` عند الإلغاء. الحذف يعالجه نداء منفصل في الشاشة.
class DhikrEditorDialog extends StatefulWidget {
  const DhikrEditorDialog({super.key, this.existing});

  /// الذكر المعدَّل — null يعني إضافة جديدة.
  final UserDhikr? existing;

  @override
  State<DhikrEditorDialog> createState() => _DhikrEditorDialogState();
}

class _DhikrEditorDialogState extends State<DhikrEditorDialog> {
  static const _presets = <int>[1, 3, 7, 10, 33, 100];

  late final TextEditingController _text = TextEditingController(
    text: widget.existing?.text ?? '',
  );
  late final TextEditingController _source = TextEditingController(
    text: widget.existing?.source ?? '',
  );
  late int _repeat = widget.existing?.repeat ?? 1;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _source.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(
        () => _error = context.tr(
          'اكتب نص الذكر أولاً',
          'Write the dhikr text first',
        ),
      );
      return;
    }
    if (text.length > kUserDhikrMaxLength) {
      setState(
        () => _error = 'النص طويل جداً (الحد $kUserDhikrMaxLength حرفاً)',
      );
      return;
    }
    final source = _source.text.trim();
    final existing = widget.existing;
    final result = existing == null
        ? UserDhikr.create(text: text, repeat: _repeat, source: source)
        : existing.copyWith(
            text: text,
            repeat: _repeat.clamp(1, kUserDhikrMaxRepeat),
            source: source,
          );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(
        isEditing
            ? context.tr('تعديل الذكر', 'Edit dhikr')
            : context.tr('إضافة ذكر', 'Add dhikr'),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _text,
                minLines: 4,
                maxLines: 8,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText: context.tr('نص الذكر', 'Dhikr text'),
                  hintText: 'مثال: سُبْحَانَ اللهِ وَبِحَمْدِهِ',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('عدد التكرار', 'Repetitions'),
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in _presets)
                    ChoiceChip(
                      label: Text(context.digits(preset)),
                      selected: _repeat == preset,
                      onSelected: (_) => setState(() => _repeat = preset),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr(
                        'مخصص (١–${context.digits(kUserDhikrMaxRepeat)})',
                        'Custom (1–$kUserDhikrMaxRepeat)',
                      ),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: _repeat > 1
                        ? () => setState(() => _repeat -= 1)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      context.digits(_repeat),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: _repeat < kUserDhikrMaxRepeat
                        ? () => setState(() => _repeat += 1)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _source,
                decoration: InputDecoration(
                  labelText: context.tr(
                    'المصدر (اختياري)',
                    'Source (optional)',
                  ),
                  hintText: context.tr(
                    'مثال: رواه مسلم',
                    'e.g. Narrated by Muslim',
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'يُحفظ على جهازك فقط، ولا يُرسل لأي سيرفر.',
                  'Saved on your device only, never sent to any server.',
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            isEditing ? context.tr('حفظ', 'Save') : context.tr('إضافة', 'Add'),
          ),
        ),
      ],
    );
  }
}
