/// Failure reported by the embedded VRM runtime.
final class VrmRuntimeException implements Exception {
  const VrmRuntimeException({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'VrmRuntimeException($code): $message';
}
