import 'package:flutter/material.dart';

import 'package:yousuf/core/l10n/tr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/quran_reciter.dart';
import 'quran_providers.dart';

/// ورقة اختيار القارئ — تُستخدم في قارئ المصحف ومركز التحميلات.
class ReciterPickerSheet extends ConsumerWidget {
  const ReciterPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(quranReciterProvider);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Text(
                  context.tr('اختر القارئ', 'Choose reciter'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  context.tr(
                    'سيُستخدم للاستماع والتحميل',
                    'Used for listening and downloads',
                  ),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: kQuranReciters.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reciter = kQuranReciters[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reciter.nameAr),
                  subtitle: Text(reciter.subtitle),
                  trailing: reciter.id == current.id
                      ? Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () async {
                    await ref
                        .read(quranReciterProvider.notifier)
                        .select(reciter);
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// يفتح ورقة اختيار القارئ (يُحفظ الاختيار مباشرة).
Future<void> showReciterPicker(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const ReciterPickerSheet(),
    );
