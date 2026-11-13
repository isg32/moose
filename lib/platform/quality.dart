/// The audio quality setting (Settings → Audio quality).
///
/// YouTube offers a handful of audio-only streams per video, usually around
/// 50, 70, 128 and 160 kbps. Best and Low take the extremes; High and Medium
/// take the stream closest to their target. The NewPipe fallback
/// (`YouTubeChannel.kt`) applies the same rule.
enum AudioQuality {
  best('Best', null),
  high('High', 160),
  medium('Medium', 128),
  low('Low', null);

  const AudioQuality(this.label, this.targetKbps);

  final String label;

  /// The bitrate High and Medium aim for.
  final int? targetKbps;

  /// The approximate bitrate shown under the setting.
  String get hint => switch (this) {
    best => 'The highest YouTube offers, usually about 160 kbps.',
    high => 'About 160 kbps.',
    medium => 'About 128 kbps.',
    low => 'The lowest, about 50 kbps. Saves data and space.',
  };

  static AudioQuality parse(String? name) => AudioQuality.values.firstWhere(
    (q) => q.name == name,
    orElse: () => AudioQuality.best,
  );
}

/// One audio-only stream on offer.
class AudioCandidate<T> {
  const AudioCandidate({
    required this.kbps,
    required this.m4a,
    required this.value,
  });

  final double kbps;

  /// MP4/M4A container (plays everywhere); preferred over WebM on ties.
  final bool m4a;
  final T value;
}

/// The stream [quality] asks for, or null when there are none.
T? pickAudio<T>(List<AudioCandidate<T>> streams, AudioQuality quality) {
  if (streams.isEmpty) return null;
  int m4aFirst(AudioCandidate<T> a, AudioCandidate<T> b) =>
      (b.m4a ? 1 : 0) - (a.m4a ? 1 : 0);
  final sorted = [...streams];
  switch (quality) {
    case AudioQuality.best:
      sorted.sort((a, b) {
        final c = b.kbps.compareTo(a.kbps);
        return c != 0 ? c : m4aFirst(a, b);
      });
    case AudioQuality.low:
      sorted.sort((a, b) {
        final c = a.kbps.compareTo(b.kbps);
        return c != 0 ? c : m4aFirst(a, b);
      });
    case AudioQuality.high:
    case AudioQuality.medium:
      final target = quality.targetKbps!;
      sorted.sort((a, b) {
        final c = (a.kbps - target).abs().compareTo((b.kbps - target).abs());
        return c != 0 ? c : m4aFirst(a, b);
      });
  }
  return sorted.first.value;
}
