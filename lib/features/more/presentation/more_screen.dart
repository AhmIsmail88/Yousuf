import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:yousuf/core/l10n/tr.dart';

/// «المزيد» — كل أقسام التطبيق في مكان واحد (لا تفتح الإعدادات مباشرة).
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = <(String, List<_Entry>)>[
      (
        context.tr('العبادات', 'Worship'),
        [
          _Entry(
            Icons.menu_book_outlined,
            context.tr('المصحف', 'Quran'),
            '/quran',
            tab: true,
          ),
          _Entry(
            Icons.auto_awesome_outlined,
            context.tr('الأذكار', 'Adhkar'),
            '/adhkar',
            tab: true,
          ),
          _Entry(
            Icons.mosque_outlined,
            context.tr('مواقيت الصلاة', 'Prayer times'),
            '/prayer',
            tab: true,
          ),
          _Entry(
            Icons.explore_outlined,
            context.tr('القبلة', 'Qibla'),
            '/qibla',
          ),
          _Entry(
            Icons.radio_button_checked,
            context.tr('المسبحة', 'Tasbih'),
            '/tasbih',
          ),
          _Entry(
            Icons.auto_stories_outlined,
            context.tr('الختمة', 'Khatma'),
            '/khatma',
          ),
        ],
      ),
      (
        context.tr('العلم والمعرفة', 'Knowledge'),
        [
          _Entry(
            Icons.library_books_outlined,
            context.tr('الحديث', 'Hadith'),
            '/hadith',
          ),
          _Entry(
            Icons.local_library_outlined,
            context.tr('المكتبة', 'Library'),
            '/history',
          ),
          _Entry(
            Icons.calendar_month_outlined,
            context.tr('التقويم', 'Calendar'),
            '/calendar',
          ),
        ],
      ),
      (
        context.tr('الأسرة', 'Family'),
        [
          _Entry(
            Icons.child_care_outlined,
            context.tr('الأطفال', 'Kids'),
            '/kids',
          ),
        ],
      ),
      (
        context.tr('التطبيق', 'App'),
        [
          _Entry(
            Icons.download_for_offline_outlined,
            context.tr('التحميلات', 'Downloads'),
            '/downloads',
          ),
          _Entry(
            Icons.settings_outlined,
            context.tr('الإعدادات', 'Settings'),
            '/settings',
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('المزيد', 'More'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final (title, entries) in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
              children: [for (final entry in entries) _Tile(entry: entry)],
            ),
          ],
        ],
      ),
    );
  }
}

class _Entry {
  const _Entry(this.icon, this.label, this.route, {this.tab = false});

  final IconData icon;
  final String label;
  final String route;
  final bool tab;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (entry.tab) {
            context.go(entry.route);
          } else {
            context.push(entry.route);
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(entry.icon, color: scheme.primary, size: 26),
            const SizedBox(height: 8),
            Text(
              entry.label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
