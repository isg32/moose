import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../core/theme/v_palette.dart';
import '../core/theme/v_text.dart';
import '../core/theme/v_tokens.dart';
import '../core/widgets/v_buttons.dart';
import '../core/widgets/v_glass.dart';
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
    return SizedBox.expand(
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        label: r.title,
        child: VGlass(
          radius: 0,
          border: false,
          blur: 14,
          tint: VPalette.of(context).glassSheet,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, pad.top + 24, 16, pad.bottom + 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: VOutlined(
                  radius: VRadius.sheet,
                  fill: VPalette.of(context).paper,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          r.fromLastRun ? 'LAST TIME' : 'UNEXPECTED',
                          style: VText.eyebrow,
                        ),
                        const SizedBox(height: 8),
                        Text(r.title, style: VText.doto(26, height: 1.1)),
                        const SizedBox(height: 10),
                        Text(
                          r.summary,
                          style: VText.inter(14, weight: 300, height: 1.45),
                        ),
                        const SizedBox(height: 16),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: VOutlined(
                            radius: 14,
                            outline: VOutline.dashed,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Text(r.log, style: VText.mono),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: VButton.secondary(
                                'Copy log',
                                onPressed: _copy,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: VButton.secondary(
                                'Save to Downloads',
                                onPressed: _save,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        VButton.primary(
                          'Close',
                          onPressed: CrashLog.instance.dismiss,
                        ),
                        if (_note != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _note!,
                            textAlign: TextAlign.center,
                            style: VText.secondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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
