import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/icons/v_icons.dart';
import '../../core/theme/v_text.dart';
import '../../core/widgets/v_buttons.dart';
import '../../core/widgets/v_glass.dart';
import '../../core/widgets/v_ink.dart';
import '../../core/widgets/v_progress.dart';
import '../../net/updater.dart';

/// A short line for where an update is.
String updateLine(UpdateState s) => switch (s) {
  UpdateAvailable(:final release) => '${release.sizeLabel} · tap to update',
  UpdateDownloading(:final release, :final received) =>
    'Downloading · ${megabytes(received)} of ${release.sizeLabel}',
  UpdateReady() => 'Downloaded · tap to install',
  UpdateNeedsPermission() => 'Needs your OK to install',
  UpdateInstalling(:final confirming) =>
    confirming ? 'Confirm on the screen Android shows' : 'Installing…',
  UpdateFailed(:final reinstall) =>
    reinstall
        ? 'Reinstall once from GitHub'
        : "Didn't finish · tap to try again",
  _ => '',
};

/// Whether [s] is worth a card: there is a newer Moose to get.
bool showsUpdate(UpdateState s) => s.release != null;

/// "Moose 0.32.0 is out": in Chat (closable) and in Settings. Tapping it
/// opens [showUpdateSheet].
class UpdateCard extends ConsumerWidget {
  const UpdateCard({super.key, this.closable = false});

  /// Chat's card can be closed until a newer version comes.
  final bool closable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updaterProvider);
    final release = s.release;
    if (release == null) return const SizedBox.shrink();
    if (closable && ref.watch(dismissedUpdateProvider) == release.version) {
      return const SizedBox.shrink();
    }
    final busy =
        s is UpdateDownloading || (s is UpdateInstalling && !s.confirming);
    return Semantics(
      button: true,
      label: 'Moose ${release.version} is out. ${updateLine(s)}',
      excludeSemantics: true,
      child: VTappable(
        onTap: () => showUpdateSheet(context),
        child: VGlass(
          radius: 18,
          // Solid: it floats over the messages, which mustn't show through.
          tint: VInk.surfaceOf(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 34,
                  child: switch (s) {
                    UpdateDownloading(:final progress) => VRing(
                      value: progress,
                      size: 34,
                      strokeWidth: 3,
                    ),
                    _ when busy => const VSpinner(size: 30),
                    UpdateFailed() => const Center(
                      child: VIconView(VIcon.warning, size: 22),
                    ),
                    _ => const Center(
                      child: VIconView(VIcon.download, size: 22),
                    ),
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Moose ${release.version} is out',
                        style: VText.inter(14, weight: 600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        updateLine(s),
                        style: VText.secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (closable)
                  Semantics(
                    button: true,
                    label: 'Hide',
                    child: VTappable(
                      onTap: () => ref.read(updaterProvider.notifier).dismiss(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: VIconView(VIcon.close, size: 18),
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: VIconView(VIcon.chevron, size: 18),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The update, what's new in it, and one button that downloads, then
/// installs.
Future<void> showUpdateSheet(BuildContext context) => showVSheet<void>(
  context,
  title: 'Update',
  builder: (_) => const _UpdateSheet(),
);

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updaterProvider);
    final up = ref.read(updaterProvider.notifier);
    final release = s.release;
    if (release == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          s is UpdateFailed ? s.message : "You're on the latest Moose.",
          style: VText.body,
        ),
      );
    }
    final Widget action = switch (s) {
      UpdateAvailable() => VButton.primary(
        'Update · ${release.sizeLabel}',
        onPressed: () {
          HapticFeedback.selectionClick();
          up.download();
        },
      ),
      UpdateDownloading(:final received, :final progress) => _Progress(
        value: progress,
        label: '${megabytes(received)} of ${release.sizeLabel}',
      ),
      UpdateReady() => VButton.primary(
        'Install',
        onPressed: () {
          HapticFeedback.selectionClick();
          up.install();
        },
      ),
      UpdateNeedsPermission() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Android asks for your OK once, so Moose can install its own '
            'updates. Turn on "Allow from this source", then come back.',
            style: VText.secondary,
          ),
          const SizedBox(height: 12),
          VButton.primary('Allow', onPressed: up.allowInstalls),
        ],
      ),
      UpdateInstalling(:final confirming) => _Progress(
        label: confirming
            ? 'Confirm on the screen Android shows'
            : 'Installing… Moose closes when it’s done',
      ),
      UpdateFailed(:final message, :final reinstall) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message, style: VText.secondary),
          const SizedBox(height: 12),
          if (reinstall)
            VButton.primary(
              'Open GitHub',
              onPressed: () => launchUrl(
                Uri.parse(releasesPageUrl),
                mode: LaunchMode.externalApplication,
              ),
            )
          else
            VButton.primary(
              'Try again',
              onPressed: () {
                up.clearFailure();
                up.download();
              },
            ),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Moose ${release.version}', style: VText.doto(26, weight: 800)),
        const SizedBox(height: 4),
        Text(release.sizeLabel, style: VText.secondary),
        if (release.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text("WHAT'S NEW", style: VText.eyebrow),
          const SizedBox(height: 8),
          _Notes(release.notes),
        ],
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(key: ValueKey(s.runtimeType), child: action),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label, this.value});

  /// 0–1, or null while it can't tell (a spinner).
  final double? value;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: Row(
      children: [
        if (value == null)
          const VSpinner(size: 26)
        else
          VRing(value: value!, size: 30, strokeWidth: 3),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: VText.inter(14, weight: 500)),
              if (value != null) ...[
                const SizedBox(height: 8),
                VBar(value: value!, height: 4),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Notes extends StatelessWidget {
  const _Notes(this.notes);
  final List<String> notes;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // Long lists scroll rather than push the button off the sheet.
    constraints: const BoxConstraints(maxHeight: 220),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: VInk.of(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(child: Text(n, style: VText.body)),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Once, after Moose updated itself: what changed.
Future<void> showWhatsNew(BuildContext context, UpdateRelease release) =>
    showVSheet<void>(
      context,
      title: "What's new",
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Moose ${release.version}', style: VText.doto(26, weight: 800)),
          const SizedBox(height: 14),
          if (release.notes.isEmpty)
            Text('Fixes and polish.', style: VText.body)
          else
            _Notes(release.notes),
          const SizedBox(height: 18),
          VButton.primary('Nice', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
