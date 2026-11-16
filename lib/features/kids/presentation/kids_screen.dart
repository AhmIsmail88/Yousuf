import 'package:flutter/material.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/app/theme/app_colors.dart';

import '../domain/kid_profile.dart';
import 'kid_learning_screens.dart';
import 'tuhfa_screen.dart';
import 'kids_providers.dart';

/// بوابة وضع الأطفال: اختيار ملف أو إنشاء ملف جديد (SPEC §7.9).
class KidsScreen extends ConsumerWidget {
  const KidsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(kidProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('وضع الأطفال', 'Kids mode'))),
      body: profiles.isEmpty
          ? _EmptyKids(onCreate: () => _createProfile(context, ref))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  context.tr('من يقرأ اليوم؟', 'Who is reading today?'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                  children: [
                    for (final profile in profiles)
                      _ProfileCard(
                        profile: profile,
                        onTap: () async {
                          await ref
                              .read(activeKidProvider.notifier)
                              .select(profile);
                          if (!context.mounted) return;
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const KidHomeScreen(),
                            ),
                          );
                        },
                        onDelete: () => _deleteProfile(context, ref, profile),
                      ),
                    _AddProfileCard(onTap: () => _createProfile(context, ref)),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _createProfile(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<KidProfile>(
      context: context,
      builder: (_) => const _KidProfileDialog(),
    );
    if (result == null) return;
    final created = await ref
        .read(kidProfilesProvider.notifier)
        .add(result.name, result.avatar);
    await ref.read(activeKidProvider.notifier).select(created);
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const KidHomeScreen()));
  }

  Future<void> _deleteProfile(
    BuildContext context,
    WidgetRef ref,
    KidProfile profile,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('حذف الملف؟', 'Delete profile?')),
        content: Text(
          context.tr(
            'سيُحذف ملف ${profile.name} ونجومه.',
            'The profile of ${profile.name} and its stars will be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(kidProfilesProvider.notifier).remove(profile.id);
    }
  }
}

class _EmptyKids extends StatelessWidget {
  const _EmptyKids({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🌙', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'أهلاً بكم في ركن الأطفال',
                'Welcome to the kids corner',
              ),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'ملف باسم وصورة، جزء عمّ بالتلقين والنجوم، وأذكار مبسّطة.',
                'A profile with a name and picture, Quran with a teaching reciter and stars, and simple adhkar.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.7),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(context.tr('أنشئ ملف طفل', 'Create a child profile')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onTap,
    required this.onDelete,
  });

  final KidProfile profile;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    profile.avatarEmoji,
                    style: const TextStyle(fontSize: 46),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${context.digits(profile.stars)} ⭐',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              top: 2,
              start: 2,
              child: IconButton(
                tooltip: context.tr('حذف', 'Delete'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16),
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_circle_outline,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('إضافة طفل', 'Add child'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _KidProfileDialog extends StatefulWidget {
  const _KidProfileDialog();

  @override
  State<_KidProfileDialog> createState() => _KidProfileDialogState();
}

class _KidProfileDialogState extends State<_KidProfileDialog> {
  final TextEditingController _name = TextEditingController();
  int _avatar = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('ملف طفل جديد', 'New child profile')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: context.tr('الاسم', 'Name')),
          ),
          const SizedBox(height: 14),
          Text(context.tr('الصورة الرمزية', 'Avatar')),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (var index = 0; index < kidAvatars.length; index++)
                ChoiceChip(
                  label: Text(
                    kidAvatars[index],
                    style: const TextStyle(fontSize: 20),
                  ),
                  selected: _avatar == index,
                  onSelected: (_) => setState(() => _avatar = index),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            KidProfile(
              id: '',
              name: _name.text.trim().isEmpty ? 'صديق يوسف' : _name.text.trim(),
              avatar: _avatar,
            ),
          ),
          child: Text(context.tr('إنشاء', 'Create')),
        ),
      ],
    );
  }
}

/// شاشة الطفل: النجوم، جزء عمّ، الأذكار، والخروج برمز.
class KidHomeScreen extends ConsumerWidget {
  const KidHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kid = ref.watch(activeKidProvider);
    final progress = ref.watch(kidProgressProvider);
    final theme = Theme.of(context);

    if (kid == null) {
      return Scaffold(
        body: Center(
          child: Text(context.tr('لا يوجد ملف طفل', 'No child profile')),
        ),
      );
    }

    final total = KidProfile.totalSurahs;

    return Scaffold(
      appBar: AppBar(
        title: Text('${kid.avatarEmoji}  ${kid.name}'),
        actions: [
          IconButton(
            tooltip: context.tr('خروج من وضع الأطفال', 'Exit kids mode'),
            icon: const Icon(Icons.lock_outline),
            onPressed: () => _exit(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [AppColors.deepTeal, Color(0xFF3F8794)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const Text('⭐', style: TextStyle(fontSize: 34)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          'نجومك: ${context.digits(progress.stars)}',
                          'Your stars: ${progress.stars}',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        context.tr(
                          'سمّعت ${context.digits(progress.memorizedAyat.length)} آية · أتممت ${context.digits(progress.completedSurahs.length)} من ${context.digits(total)} سورة',
                          'Recited ${progress.memorizedAyat.length} ayahs · completed ${progress.completedSurahs.length} of $total surahs',
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _KidTile(
            emoji: '📖',
            title: context.tr('القرآن', 'Quran'),
            subtitle: context.tr(
              'اختر أي سورة من ثلاثين جزءاً',
              'Pick any surah and recite it by heart',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const KidQuranBrowserScreen(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _KidTile(
            emoji: '🌤️',
            title: context.tr('أذكار الطفل', 'Kids adhkar'),
            subtitle: context.tr(
              'أذكار الصباح بخط كبير',
              'Morning adhkar in large print',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const KidAdhkarScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _KidTile(
            emoji: '🎙️',
            title: context.tr('تحفة الأطفال', 'Tuhfat al-Atfal'),
            subtitle: context.tr(
              'أحكام التجويد في أبيات مع الصوت',
              'Tajweed rules in verse, with audio',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TuhfaScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _KidTile(
            emoji: '🏅',
            title: context.tr('لوحة النجوم', 'Star board'),
            subtitle: context.tr(
              'شاهد كل ما أنجزته',
              'See everything you achieved',
            ),
            onTap: () => _showStars(context, ref),
          ),
          const SizedBox(height: 10),
          _KidTile(
            emoji: '🔒',
            title: ref.watch(kidPinProvider) == null
                ? context.tr('تعيين رمز الخروج', 'Set exit PIN')
                : context.tr('تغيير رمز الخروج', 'Change exit PIN'),
            subtitle: context.tr(
              'حتى لا يخرج الطفل من التطبيق',
              'So the child cannot leave kids mode',
            ),
            onTap: () => _setPin(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _exit(BuildContext context, WidgetRef ref) async {
    final pin = ref.read(kidPinProvider);
    if (pin == null) {
      await ref.read(activeKidProvider.notifier).select(null);
      if (context.mounted)
        Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    final entered = await _askPin(context);
    if (entered == pin) {
      await ref.read(activeKidProvider.notifier).select(null);
      if (context.mounted)
        Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('الرمز غير صحيح', 'Wrong PIN'))),
      );
    }
  }

  Future<void> _setPin(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _PinDialog(
        title: context.tr('رمز الخروج (٤ أرقام)', 'Exit PIN (4 digits)'),
      ),
    );
    if (result == null) return;
    await ref.read(kidPinProvider.notifier).set(result);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isEmpty
              ? context.tr('أُلغي الرمز', 'PIN removed')
              : context.tr('حُفظ الرمز', 'PIN saved'),
        ),
      ),
    );
  }

  Future<String?> _askPin(BuildContext context) => showDialog<String>(
    context: context,
    builder: (_) =>
        _PinDialog(title: context.tr('أدخل رمز الخروج', 'Enter the exit PIN')),
  );

  void _showStars(BuildContext context, WidgetRef ref) {
    final progress = ref.read(kidProgressProvider);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('لوحة النجوم', 'Star board')),
        content: Text(
          progress.stars == 0
              ? context.tr(
                  'لا نجوم بعد — سمّع أول آية من حفظك لتأخذ نجمتك الأولى!',
                  'No stars yet — recite your first ayah by heart to earn one!',
                )
              : context.tr(
                  '⭐ ${context.digits(progress.stars)} نجمة: ${context.digits(progress.memorizedAyat.length)} آية سمّعتها و${context.digits(progress.completedSurahs.length)} سورة أتممتها. بارك الله فيك!',
                  '⭐ ${progress.stars} stars: ${progress.memorizedAyat.length} ayahs recited and ${progress.completedSurahs.length} surahs completed. May Allah bless you!',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('حسناً', 'OK')),
          ),
        ],
      ),
    );
  }
}

class _KidTile extends StatelessWidget {
  const _KidTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(subtitle, style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.title});

  final String title;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(counterText: ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(context.tr('حفظ', 'Save')),
        ),
      ],
    );
  }
}
