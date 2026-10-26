import 'dart:async';

/// In-process notification only after the local Job status write + durable
/// outbox entry have committed. It never denotes a completed remote sync.
class LocalJobStatusChanged {
  const LocalJobStatusChanged({
    required this.businessId,
    required this.jobId,
    required this.code,
    required this.name,
    this.colorHex,
    this.iconKey,
  });

  final String businessId;
  final String jobId;
  final String code;
  final String name;
  final String? colorHex;
  final String? iconKey;
}

class LocalJobStatusEvents {
  LocalJobStatusEvents._();

  static final StreamController<LocalJobStatusChanged> _controller =
      StreamController<LocalJobStatusChanged>.broadcast(sync: true);

  static Stream<LocalJobStatusChanged> get changes => _controller.stream;

  static void committed(LocalJobStatusChanged event) {
    _controller.add(event);
  }
}
