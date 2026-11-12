import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../data/providers.dart';
import '../common/overlay.dart';

/// Opens the poke picker under the header's poke button (C24) and returns
/// the moment picked.
Future<VMoment?> showPokePicker(
  BuildContext context, {
  required String partner,
}) => showOverlayPage<VMoment>(context, (_) => PokePicker(partner: partner));

class PokePicker extends ConsumerStatefulWidget {
  const PokePicker({super.key, required this.partner});

  final String partner;

  @override
  ConsumerState<PokePicker> createState() => _PokePickerState();
}

class _PokePickerState extends ConsumerState<PokePicker> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Count the cooldowns down while the picker is open.
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(momentCooldownProvider);
    final cd = ref.read(momentCooldownProvider.notifier);
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: ColoredBox(color: VPalette.of(context).popupScrim),
          ),
        ),
        Positioned(
          right: 14,
          top: top + 72,
          width: 300,
          child: VGlass(
            radius: 28,
            tint: VPalette.of(context).glassSheet,
            blur: 14,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'SEND ${widget.partner.toUpperCase()} A…',
                        style: VText.eyebrow,
                      ),
                      const Spacer(),
                      Text('tap to send', style: VText.secondary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 131 / 112,
                    children: [
                      for (final m in VMoment.values)
                        _Tile(
                          moment: m,
                          wait: cd.left(m),
                          onTap: () {
                            if (cd.left(m) > Duration.zero) {
                              HapticFeedback.heavyImpact();
                              return;
                            }
                            Navigator.of(context).pop(m);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'One of each every 10 seconds, so they stay special.',
                    style: VText.secondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.moment, required this.wait, required this.onTap});

  final VMoment moment;
  final Duration wait;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cooling = wait > Duration.zero;
    return Semantics(
      button: true,
      label: cooling
          ? '${moment.label}, ready in ${wait.inSeconds + 1} seconds'
          : 'Send a ${moment.label}',
      child: VTappable(
        onTap: onTap,
        child: Opacity(
          opacity: cooling ? 0.45 : 1,
          child: Container(
            decoration: BoxDecoration(
              color: moment.color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        moment.emoji,
                        style: const TextStyle(fontSize: 38, height: 1),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        moment.label,
                        style: VText.inter(
                          13,
                          weight: 600,
                        ).copyWith(color: VColors.black),
                      ),
                    ],
                  ),
                ),
                if (cooling)
                  Positioned(
                    top: 8,
                    right: 10,
                    child: Text(
                      '${wait.inSeconds + 1}s',
                      style: VText.doto(12).copyWith(color: VColors.black),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
