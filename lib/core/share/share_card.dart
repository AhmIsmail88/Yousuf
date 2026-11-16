import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:yousuf/core/utils/quran_text.dart';
import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import 'package:yousuf/app/theme/app_colors.dart';

/// ورقة مشاركة محتوى شرعي كصورة: معاينة + مشاركة + نسخ النص.
Future<void> showShareSheet(
  BuildContext context, {
  required String text,
  required String source,
  String? title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ShareContentSheet(text: text, source: source, title: title),
  );
}

class ShareContentSheet extends StatefulWidget {
  const ShareContentSheet({
    super.key,
    required this.text,
    required this.source,
    this.title,
  });

  final String text;
  final String source;
  final String? title;

  @override
  State<ShareContentSheet> createState() => _ShareContentSheetState();
}

class _ShareContentSheetState extends State<ShareContentSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  Future<void> _shareImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final noImage = context.tr(
      'تعذر إنشاء الصورة',
      'Could not create the image',
    );
    final failed = context.tr('تعذر المشاركة', 'Could not share');
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null)
        throw StateError(
          context.tr('لا يمكن رسم البطاقة', 'Cannot render the card'),
        );
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError(noImage);
      final directory = Directory.systemTemp;
      final file = File(
        '${directory.path}/yousuf_share_'
        '${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '${widget.text}\n\n${widget.source}\n— تطبيق يوسف',
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  context.tr('مشاركة', 'Share'),
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  context.tr('كصورة أو نص', 'As image or text'),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: ShareCard(
                        text: widget.text,
                        source: widget.source,
                        title: widget.title,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _shareImage,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share, size: 18),
                    label: Text(context.tr('مشاركة كصورة', 'Share as image')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await SharePlus.instance.share(
                        ShareParams(
                          text:
                              '${widget.text}\n\n${widget.source}\n— تطبيق يوسف',
                        ),
                      );
                    },
                    icon: const Icon(Icons.text_fields, size: 18),
                    label: Text(context.tr('نص فقط', 'Text only')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة المشاركة: خلفية فيروزية، نص بخط Amiri، والمصدر، وهوية التطبيق.
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.text,
    required this.source,
    this.title,
  });

  final String text;
  final String source;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.deepTeal, Color(0xFF3F8794)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Text(
              title!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'IBM Plex Sans Arabic',
              ),
            ),
          const SizedBox(height: 14),
          Text(
            quranFontText(text),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: AppTheme.quranFont,
              fontFamilyFallback: AppTheme.quranFallback,
              fontSize: 21,
              height: 2.0,
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 10),
          Text(
            source,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'IBM Plex Sans Arabic',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/brand/logo_white.png',
                height: 22,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 8),
              const Text(
                'رفيقك في الطاعة',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  fontFamily: 'IBM Plex Sans Arabic',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
