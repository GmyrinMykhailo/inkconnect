import 'dart:async';

typedef AutoRefreshCallback = Future<void> Function();

class AutoRefreshController {
  AutoRefreshController({
    required this.interval,
    required this.onRefresh,
  });

  final Duration interval;
  final AutoRefreshCallback onRefresh;

  Timer? _timer;
  bool _refreshing = false;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => _tick());
  }

  void restart() {
    stop();
    start();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();

  Future<void> _tick() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      await onRefresh();
    } finally {
      _refreshing = false;
    }
  }
}
