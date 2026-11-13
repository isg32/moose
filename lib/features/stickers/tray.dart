import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_colors.dart';
import '../../core/theme/v_palette.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_controls.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_surface.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../net/web_memes.dart';
import '../common/art.dart';
import '../common/choice_sheet.dart';
import '../common/dot_loader.dart';
import '../common/overlay.dart';
import '../common/parts.dart';
import '../common/sticker_view.dart';
import 'sticker_maker.dart';

enum TrayTab { stickers, gifs, memes }

/// The sticker, GIF and meme tray (S1, C26), from the composer's sticker
/// button. Returns what to send.
Future<Body?> showTray(
  BuildContext context, {
  TrayTab start = TrayTab.stickers,
}) => showOverlayPage<Body>(context, (_) => Tray(start: start));

class Tray extends ConsumerStatefulWidget {
  const Tray({super.key, this.start = TrayTab.stickers});

  final TrayTab start;

  @override
  ConsumerState<Tray> createState() => _TrayState();
}

class _TrayState extends ConsumerState<Tray> {
  late var _tab = widget.start;

  @override
  Widget build(BuildContext context) {
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
          left: 0,
          right: 0,
          bottom: 0,
          top: top + 70,
          child: VGlass(
            radius: 28,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            tint: VPalette.of(context).glassSheet,
            blur: 14,
            border: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: VInk.of(context))),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: VInk.of(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    VSegmented<TrayTab>(
                      segments: const {
                        TrayTab.stickers: 'Stickers',
                        TrayTab.gifs: 'GIFs',
                        TrayTab.memes: 'Memes',
                      },
                      value: _tab,
                      onChanged: (t) => setState(() => _tab = t),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _tab == TrayTab.stickers
                          ? const _Stickers()
                          : _Memes(
                              key: ValueKey(_tab),
                              kind: _tab == TrayTab.gifs
                                  ? MemeKind.gif
                                  : MemeKind.meme,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A search field in an outlined pill (A6).
class SearchPill extends StatelessWidget {
  const SearchPill({
    super.key,
    required this.controller,
    required this.placeholder,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final ink = VInk.of(context);
    return VOutlined(
      radius: 999,
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 16),
            child: VIconView(VIcon.search, size: 18),
          ),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              placeholder: placeholder,
              placeholderStyle: VText.inter(15).copyWith(color: ink),
              style: VText.inter(15).copyWith(color: ink),
              cursorColor: ink,
              padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
              decoration: const BoxDecoration(color: VColors.transparent),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, v, _) => v.text.isEmpty
                ? const SizedBox(width: 12)
                : Semantics(
                    button: true,
                    label: 'Clear',
                    child: VTappable(
                      onTap: () {
                        controller.clear();
                        onChanged?.call('');
                      },
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(6, 10, 16, 10),
                        child: VIconView(VIcon.close, size: 18),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// S1: your stickers, by pack.
class _Stickers extends ConsumerStatefulWidget {
  const _Stickers();

  @override
  ConsumerState<_Stickers> createState() => _StickersState();
}

class _StickersState extends ConsumerState<_Stickers> {
  final _search = TextEditingController();

  /// null = favourites, '' = recent, else a pack id.
  String? _pack;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    final made = await makeSticker(context, ref);
    if (made != null && mounted) Navigator.of(context).pop(StickerBody(made));
  }

  Future<void> _hold(Sticker s) async {
    unawaited(HapticFeedback.mediumImpact());
    final fav = await showChoiceSheet<String>(
      context,
      title: 'Sticker',
      choices: [
        Choice(
          'fav',
          s.favourite ? 'Remove from favourites' : 'Add to favourites',
          icon: VIcon.star,
        ),
        const Choice('remove', 'Remove sticker', icon: VIcon.trash),
      ],
    );
    if (!mounted) return;
    final n = ref.read(stickersProvider.notifier);
    if (fav == 'fav') n.toggleFavourite(s.id);
    if (fav == 'remove') n.remove(s.id);
  }

  @override
  Widget build(BuildContext context) {
    final packs = ref.watch(stickersProvider);
    final all = [for (final p in packs) ...p.stickers];
    final List<Sticker> shown;
    final String label;
    if (_pack == null) {
      shown = all.where((s) => s.favourite).toList();
      label = 'Favourites';
    } else if (_pack!.isEmpty) {
      shown = all.take(8).toList();
      label = 'Recent';
    } else {
      final p = packs.firstWhere(
        (p) => p.id == _pack,
        orElse: () => packs.first,
      );
      shown = p.stickers;
      label = p.name;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchPill(controller: _search, placeholder: 'Search your stickers'),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _PackTab(
                selected: _pack == '',
                label: 'Recent',
                onTap: () => setState(() => _pack = ''),
                child: const VIconView(VIcon.pending, size: 20),
              ),
              _PackTab(
                selected: _pack == null,
                label: 'Favourites',
                onTap: () => setState(() => _pack = null),
                child: VIconView(
                  VIcon.star,
                  size: 20,
                  color: _pack == null ? VInk.surfaceOf(context) : null,
                ),
              ),
              for (final p in packs)
                _PackTab(
                  selected: _pack == p.id,
                  label: 'Pack: ${p.name}',
                  onTap: () => setState(() => _pack = p.id),
                  child: p.stickers.isEmpty
                      ? const SizedBox.shrink()
                      : StickerView(
                          p.stickers.first,
                          size: 28,
                          border: 2,
                          shadow: false,
                        ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Semantics(
                  button: true,
                  label: 'Make a sticker',
                  child: VTappable(
                    onTap: _make,
                    child: const SizedBox.square(
                      dimension: 40,
                      child: VOutlined(
                        radius: 12,
                        outline: VOutline.dashed,
                        child: Center(child: VIconView(VIcon.plus, size: 20)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const VDivider(),
        const SizedBox(height: 12),
        Text(label.toUpperCase(), style: VText.eyebrow),
        const SizedBox(height: 10),
        Expanded(
          child: shown.isEmpty
              ? const Align(
                  alignment: Alignment.topCenter,
                  child: EmptyCard(
                    title: 'No stickers yet',
                    body: 'Make one from a photo or a doodle with +.',
                  ),
                )
              : GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  padding: const EdgeInsets.only(bottom: 30),
                  children: [
                    for (final (i, s) in shown.indexed)
                      Semantics(
                        button: true,
                        label: 'Sticker',
                        child: GestureDetector(
                          onLongPress: () => _hold(s),
                          child: VTappable(
                            onTap: () =>
                                Navigator.of(context).pop(StickerBody(s)),
                            child: Center(
                              child: StickerView(
                                s,
                                size: 70,
                                tilt: ((i * 17) % 14) - 7.0,
                                border: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 8,
          ),
          child: Text(
            'Long-press a sticker to favourite or remove it',
            style: VText.secondary,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _PackTab extends StatelessWidget {
  const _PackTab({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Semantics(
      button: true,
      selected: selected,
      label: label,
      child: VTappable(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? VInk.of(context) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    ),
  );
}

/// C26: GIFs and memes from KLIPY or Reddit, searchable.
class _Memes extends ConsumerStatefulWidget {
  const _Memes({super.key, required this.kind});

  final MemeKind kind;

  @override
  ConsumerState<_Memes> createState() => _MemesState();
}

class _MemesState extends ConsumerState<_Memes> {
  final _search = TextEditingController();
  // KLIPY first, as the canvas has it; Reddit when there's no KLIPY key.
  late var _source = ref.read(onNeonProvider) && !WebMemes.hasKlipy
      ? MemeSource.reddit
      : MemeSource.klipy;
  late MemeKind? _kind = widget.kind;
  var _query = '';
  Meme? _chosen;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(
      memeSearchProvider((query: _query, source: _source, kind: _kind)),
    );
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchPill(
              controller: _search,
              placeholder: 'Search memes',
              onChanged: (q) => setState(() => _query = q),
            ),
            const SizedBox(height: 10),
            VSegmented<MemeSource>(
              segments: const {
                MemeSource.klipy: 'KLIPY',
                MemeSource.reddit: 'Reddit',
              },
              value: _source,
              onChanged: (s) => setState(() => _source = s),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (k, label) in [
                    (null, 'Trending'),
                    (MemeKind.gif, 'GIFs'),
                    (MemeKind.sticker, 'Stickers'),
                    (MemeKind.meme, 'Memes'),
                    (MemeKind.clip, 'Clips'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: VPill(
                        label,
                        fill: _kind == k ? VFill.filled : VFill.outline,
                        onTap: () => setState(() => _kind = k),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: results.when(
                loading: () => const Center(child: DotLoader()),
                error: (_, _) => Align(
                  alignment: Alignment.topCenter,
                  child: _ErrorCard(
                    source: _source,
                    onRetry: () => ref.invalidate(memeSearchProvider),
                    onSwitch: () => setState(
                      () => _source = _source == MemeSource.klipy
                          ? MemeSource.reddit
                          : MemeSource.klipy,
                    ),
                  ),
                ),
                data: (memes) => memes.isEmpty
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: EmptyCard(
                          title: 'Nothing for "$_query"',
                          body: 'Check the spelling, or try fewer words.',
                        ),
                      )
                    : _Masonry(
                        memes: memes,
                        chosen: _chosen,
                        bottom: bottom + 100,
                        onTap: (m) => setState(() => _chosen = m),
                      ),
              ),
            ),
          ],
        ),
        if (_chosen != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + 14,
            child: VGlass(
              radius: 22,
              tint: VPalette.of(context).glassSheet,
              blur: 14,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  children: [
                    ArtBox(
                      art: _chosen!.art,
                      url: _chosen!.thumb ?? _chosen!.url,
                      width: 44,
                      height: 44,
                      radius: BorderRadius.circular(10),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Send this ${_chosen!.kind == MemeKind.gif ? 'GIF' : _chosen!.tag.toLowerCase()}?',
                            style: VText.inter(13, weight: 500),
                          ),
                          Text(
                            '${_chosen!.credit}${_chosen!.kind == MemeKind.gif ? ' · plays on loop' : ''}',
                            style: VText.secondary,
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Send',
                      child: VCircleButton(
                        icon: VIcon.send,
                        size: 44,
                        filled: true,
                        onTap: () =>
                            Navigator.of(context).pop(MemeBody(_chosen!)),
                      ),
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

class _Masonry extends StatelessWidget {
  const _Masonry({
    required this.memes,
    required this.chosen,
    required this.bottom,
    required this.onTap,
  });

  final List<Meme> memes;
  final Meme? chosen;
  final double bottom;
  final void Function(Meme m) onTap;

  @override
  Widget build(BuildContext context) {
    final left = <Meme>[], right = <Meme>[];
    var lh = 0.0, rh = 0.0;
    for (final m in memes) {
      if (lh <= rh) {
        left.add(m);
        lh += 1 / m.aspect;
      } else {
        right.add(m);
        rh += 1 / m.aspect;
      }
    }
    Widget column(List<Meme> ms) => Column(
      children: [
        for (final m in ms)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              button: true,
              selected: chosen == m,
              label: m.title,
              child: VTappable(
                onTap: () => onTap(m),
                child: Container(
                  decoration: chosen == m
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: VInk.of(context), width: 2),
                        )
                      : null,
                  padding: EdgeInsets.all(chosen == m ? 2 : 0),
                  child: AspectRatio(
                    aspectRatio: m.aspect,
                    child: ArtBox(
                      art: m.art,
                      url: m.thumb ?? m.url,
                      radius: BorderRadius.circular(14),
                      child: OnMedia(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: VOutlined(
                              radius: 5,
                              color: VColors.white,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                child: Text(
                                  m.tag,
                                  style: VText.inter(9, weight: 600),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: column(left)),
          const SizedBox(width: 8),
          Expanded(child: column(right)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.source,
    required this.onRetry,
    required this.onSwitch,
  });

  final MemeSource source;
  final VoidCallback onRetry;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final name = source == MemeSource.klipy ? 'KLIPY' : 'Reddit';
    final other = source == MemeSource.klipy ? 'Reddit' : 'KLIPY';
    return VCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InlineError("$name isn't answering"),
          const SizedBox(height: 6),
          Text('Try again, or switch to $other.', style: VText.secondary),
          const SizedBox(height: 10),
          Row(
            children: [
              VPill('Try again', fill: VFill.filled, onTap: onRetry),
              const SizedBox(width: 8),
              VPill(other, onTap: onSwitch),
            ],
          ),
        ],
      ),
    );
  }
}
