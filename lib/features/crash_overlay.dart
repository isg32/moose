import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../core/theme/v_text.dart';
import '../core/widgets/v_buttons.dart';
import '../core/icons/v_icons.dart';
import '../core/widgets/v_page.dart';
import '../core/widgets/v_surface.dart';
import '../platform/crash_log.dart';

/// Shows [CrashLog]'s pending report over the whole app: what happened,
/// the log, and Copy · Save to Downloads · Close.
class CrashOverlay extends StatelessWidget {
  const CrashOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // Directly in the Stack; empty (and not hit-testable) when there's
        // nothing to show.
        Positioned.fill(
          child: ValueListenableBuilder<CrashReport?>(
            valueListenable: CrashLog.instance.pending,
            builder: (context, report, _) => report == null
                ? const SizedBox.shrink()
                : _CrashCard(key: ValueKey(report), report: report),
          ),
        ),
      ],
    );
  }
}

class _CrashCard extends StatefulWidget {
  const _CrashCard({super.key, required this.report});

  final CrashReport report;

  @override
  State<_CrashCard> createState() => _CrashCardState();
}

class _CrashCardState extends State<_CrashCard> {
  String? _note;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.report.log));
    if (mounted) setState(() => _note = 'Log copied.');
  }

  Future<void> _save() async {
    try {
      final where = await CrashLog.instance.saveToDownloads(widget.report.log);
      if (mounted) setState(() => _note = 'Saved to $where');
    } on Object catch (e) {
      if (mounted) setState(() => _note = 'Couldn\'t save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final pad = MediaQuery.paddingOf(context);
    // C43: a full page over the veil: the warning, what happened, the log,
    // and the way out.
    return SizedBox.expand(
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        label: r.title,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const VVeil(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                pad.top + 72,
                20,
                pad.bottom + 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: VIconView(VIcon.warning, size: 36),
                  ),
                  const SizedBox(height: 12),
                  if (r.fromLastRun) ...[
                    Text('LAST TIME', style: VText.eyebrow),
                    const SizedBox(height: 6),
                  ],
                  Text(r.title, style: VText.doto(34, height: 1)),
                  const SizedBox(height: 12),
                  Text(
                    r.summary,
                    style: VText.inter(14, weight: 300, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: VOutlined(
                      radius: 16,
                      outline: VOutline.dashed,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Text(r.log, style: VText.mono),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  VButton.secondary('Copy details', onPressed: _copy),
                  const SizedBox(height: 12),
                  VButton.primary(
                    'Back to Moose',
                    onPressed: CrashLog.instance.dismiss,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: VLink(
                      _note ?? 'Save to Downloads',
                      style: VText.inter(13),
                      onTap: _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Replaces Flutter's red error box: a part of a page that failed to draw
/// shows a quiet dashed note (and the error goes to [CrashLog]).
Widget quietErrorWidget(FlutterErrorDetails details) => const Center(
  child: Padding(
    padding: EdgeInsets.all(12),
    child: VOutlined(
      radius: 14,
      outline: VOutline.dashed,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('This part couldn\'t be shown.'),
      ),
    ),
  ),
);
