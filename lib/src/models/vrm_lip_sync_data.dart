/// ElevenLabs & Standard TTS Phonemes/Visemes for lip sync.
enum VrmViseme {
  aa,
  ih,
  ou,
  ee,
  oh,

  /// Silence / Neutral (mouth closed)
  sil;

  /// Parses a string representation (e.g., 'AA', 'A', 'sil') into a [VrmViseme].
  /// Defaults to [VrmViseme.aa] if the string doesn't match standard visemes.
  static VrmViseme fromString(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'aa':
      case 'a':
        return VrmViseme.aa;
      case 'ih':
      case 'i':
        return VrmViseme.ih;
      case 'ou':
      case 'u':
        return VrmViseme.ou;
      case 'ee':
      case 'e':
        return VrmViseme.ee;
      case 'oh':
      case 'o':
        return VrmViseme.oh;
      case 'sil':
      case 'silence':
        return VrmViseme.sil;
      default:
        return VrmViseme.aa; // Fallback for unknown visemes
    }
  }
}

/// Selects the single input source used by a streaming speech timeline.
///
/// A timeline cannot mix amplitude and viseme frames. Start a new speech
/// session when switching input type.
enum VrmSpeechMode { viseme, amplitude }

/// A timed frame of speech viseme for speech queue playback.
class VisemeFrame implements Comparable<VisemeFrame> {
  final VrmViseme viseme;
  final double weight;
  final Duration timestamp;
  final Duration duration;

  const VisemeFrame({
    required this.viseme,
    this.weight = 1.0,
    required this.timestamp,
    this.duration = const Duration(milliseconds: 80),
  });

  /// Creates a [VisemeFrame] from a JSON map.
  factory VisemeFrame.fromJson(Map<String, dynamic> json) {
    return VisemeFrame(
      viseme: VrmViseme.fromString(json['viseme'] as String? ?? 'sil'),
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      timestamp: Duration(
        milliseconds: (json['timestampMs'] as num?)?.toInt() ?? 0,
      ),
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 80,
      ),
    );
  }

  /// Serializes the frame to a JSON map.
  Map<String, dynamic> toJson() => {
    'viseme': viseme.name,
    'weight': weight,
    'timestampMs': timestamp.inMilliseconds,
    'durationMs': duration.inMilliseconds,
  };

  @override
  int compareTo(VisemeFrame other) {
    return timestamp.compareTo(other.timestamp);
  }
}

/// A timed amplitude sample for speech timeline playback.
///
/// [duration] bounds how long the value may remain active if the next network
/// batch is late. This prevents a stalled stream from leaving the mouth open.
class AmplitudeFrame implements Comparable<AmplitudeFrame> {
  const AmplitudeFrame({
    required this.amplitude,
    required this.timestamp,
    this.duration = const Duration(milliseconds: 50),
  });

  final double amplitude;
  final Duration timestamp;
  final Duration duration;

  factory AmplitudeFrame.fromJson(Map<String, dynamic> json) {
    return AmplitudeFrame(
      amplitude: (json['amplitude'] as num?)?.toDouble() ?? 0,
      timestamp: Duration(
        milliseconds: (json['timestampMs'] as num?)?.toInt() ?? 0,
      ),
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 50,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'amplitude': amplitude,
    'timestampMs': timestamp.inMilliseconds,
    'durationMs': duration.inMilliseconds,
  };

  @override
  int compareTo(AmplitudeFrame other) => timestamp.compareTo(other.timestamp);
}
