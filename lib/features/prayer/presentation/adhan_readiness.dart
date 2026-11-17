import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/l10n/formatters.dart';
import '../../../core/l10n/tr.dart';
import '../../../core/platform/adhan_channel.dart';

/// جاهزية الأذان — تنفيذ واحد يُستخدم في الترحيب والإعدادات.
///
/// يعرض: الإشعارات، المنبّهات الدقيقة، تحسين البطارية، و«التشغيل التلقائي»
/// على أجهزة الشركات التي تقتل المنبّهات (شاومي/هواوي/أوبو/فيفو…)، مع زر
/// «جرّب الآن».
class AdhanReadinessPanel extends StatefulWidget {
  const AdhanReadinessPanel({super.key, this.dense = true});

  /// صفوف مضغوطة (الإعدادات) أو عادية (الترحيب).
  final bool dense;

  @override
  State<AdhanReadinessPanel> createState() => _AdhanReadinessPanelState();
}

class _AdhanReadinessPanelState extends State<AdhanReadinessPanel>
    with WidgetsBindingObserver {
  AdhanStatus? _status;
  bool _loading = false;
  bool _autostartVisited = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// العودة من إعدادات النظام تحدّث الحالة تلقائياً.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!AdhanChannel.isSupported) return;
    if (mounted) setState(() => _loading = true);
    try {
      final status = await AdhanChannel().status();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      debugPrint('[YousufAdhan] تعذر قراءة حالة المحرك: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestNotifications() async {
    try {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (error) {
      debugPrint('[YousufAdhan] طلب إذن الإشعارات فشل: $error');
    }
    await _refresh();
  }

  Future<void> _run(Future<bool> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('[YousufAdhan] $error');
    }
    await _refresh();
  }

  Future<void> _testAdhan() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = context.tr(
      'سيُشغَّل الأذان التجريبي بعد ٣٠ ثانية — أغلق التطبيق وانتظر',
      'A test adhan will play in 30 seconds — close the app and wait',
    );
    final failed = context.tr(
      'تعذر جدولة الأذان التجريبي',
      'Could not schedule the test adhan',
    );
    try {
      final schedule = await AdhanChannel().testAdhanIn(30);
      messenger.showSnackBar(
        SnackBar(content: Text(schedule.scheduled > 0 ? ok : failed)),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AdhanChannel.isSupported) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.tr(
            'محرك الأذان متاح على أندرويد فقط حالياً.',
            'The adhan engine is currently available on Android only.',
          ),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      );
    }
    final status = _status;
    final rows = <Widget>[
      _ReadinessRow(
        dense: widget.dense,
        title: context.tr('الإشعارات', 'Notifications'),
        hint: context.tr('لتنبيهك بموعد الصلاة', 'To alert you at prayer time'),
        ok: status?.notificationsAllowed ?? false,
        actionLabel: context.tr('السماح', 'Allow'),
        onAction: _requestNotifications,
      ),
      _ReadinessRow(
        dense: widget.dense,
        title: context.tr('المنبّهات الدقيقة', 'Exact alarms'),
        hint: context.tr(
          'لتشغيل الأذان في وقته تماماً',
          'To play the adhan exactly on time',
        ),
        ok: status?.exactAlarmAllowed ?? false,
        actionLabel: context.tr('فتح الإعدادات', 'Open settings'),
        onAction: () => _run(() => AdhanChannel().requestExactAlarm()),
      ),
      _ReadinessRow(
        dense: widget.dense,
        title: context.tr('تحسين البطارية', 'Battery optimization'),
        hint: context.tr(
          'حتى لا يؤجل النظام الأذان',
          'So the system does not delay the adhan',
        ),
        ok: !(status?.batteryOptimized ?? true),
        actionLabel: context.tr('فتح الإعدادات', 'Open settings'),
        onAction: () => _run(() => AdhanChannel().openBatterySettings()),
      ),
      if (status != null && status.alarmVolumeLow)
        _ReadinessRow(
          dense: widget.dense,
          title: context.tr('صوت المنبّه', 'Alarm volume'),
          hint: context.tr(
            'الأذان يعمل على صوت المنبّه، وهو الآن '
                '${context.digits(status.alarmVolumePercent)}٪ — ارفعه ليُسمع جيداً',
            'The adhan uses the alarm volume, now at '
                '${status.alarmVolumePercent}% — raise it',
          ),
          ok: false,
          actionLabel: context.tr('فتح الإعدادات', 'Open settings'),
          onAction: () => _run(() => AdhanChannel().openSoundSettings()),
        ),
      if (status != null && status.aggressiveOem)
        _ReadinessRow(
          dense: widget.dense,
          title: context.tr('التشغيل التلقائي', 'Autostart'),
          hint: context.tr(
            'جهازك (${status.manufacturer}) يوقف التطبيقات في الخلفية — '
                'فعّل «التشغيل التلقائي» ليوسف',
            'Your device (${status.manufacturer}) stops background apps — '
                'enable Autostart for Yousuf',
          ),
          ok: _autostartVisited,
          actionLabel: context.tr('فتح الإعدادات', 'Open settings'),
          onAction: () {
            setState(() => _autostartVisited = true);
            _run(() => AdhanChannel().openAutostartSettings());
          },
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...rows,
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.dense ? 16 : 0,
            8,
            widget.dense ? 16 : 0,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _refresh,
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(context.tr('تحديث', 'Refresh')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _testAdhan,
                  icon: const Icon(Icons.volume_up_outlined, size: 18),
                  label: Text(context.tr('جرّب الآن', 'Test now')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.dense,
    required this.title,
    required this.hint,
    required this.ok,
    required this.actionLabel,
    required this.onAction,
  });

  final bool dense;
  final String title;
  final String hint;
  final bool ok;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 16 : 0),
      leading: Icon(
        ok ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ok ? scheme.primary : scheme.outline,
        size: 20,
      ),
      title: Text(title),
      subtitle: Text(hint),
      trailing: ok
          ? Text(
              context.tr('جاهز', 'Ready'),
              style: const TextStyle(fontSize: 11),
            )
          : TextButton(onPressed: onAction, child: Text(actionLabel)),
    );
  }
}
