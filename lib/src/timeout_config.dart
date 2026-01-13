/// Configuration for request timeouts
class TimeoutConfig {
  /// Timeout for establishing connection
  final Duration? connectTimeout;

  /// Timeout for sending request data
  final Duration? sendTimeout;

  /// Timeout for receiving response data
  final Duration? receiveTimeout;

  const TimeoutConfig({
    this.connectTimeout,
    this.sendTimeout,
    this.receiveTimeout,
  });

  /// Create config with same timeout for all operations
  factory TimeoutConfig.all(Duration timeout) => TimeoutConfig(
        connectTimeout: timeout,
        sendTimeout: timeout,
        receiveTimeout: timeout,
      );

  /// Quick preset (5s connect, 10s send/receive)
  static const quick = TimeoutConfig(
    connectTimeout: Duration(seconds: 5),
    sendTimeout: Duration(seconds: 10),
    receiveTimeout: Duration(seconds: 10),
  );

  /// Standard preset (10s connect, 30s send/receive)
  static const standard = TimeoutConfig(
    connectTimeout: Duration(seconds: 10),
    sendTimeout: Duration(seconds: 30),
    receiveTimeout: Duration(seconds: 30),
  );

  /// Long-running preset (15s connect, 2min send/receive)
  static const longRunning = TimeoutConfig(
    connectTimeout: Duration(seconds: 15),
    sendTimeout: Duration(minutes: 2),
    receiveTimeout: Duration(minutes: 2),
  );

  /// Merge with another config (other takes precedence for non-null values)
  TimeoutConfig mergeWith(TimeoutConfig? other) {
    if (other == null) return this;
    return TimeoutConfig(
      connectTimeout: other.connectTimeout ?? connectTimeout,
      sendTimeout: other.sendTimeout ?? sendTimeout,
      receiveTimeout: other.receiveTimeout ?? receiveTimeout,
    );
  }

  /// Check if any timeout is configured
  bool get hasTimeouts =>
      connectTimeout != null || sendTimeout != null || receiveTimeout != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeoutConfig &&
          runtimeType == other.runtimeType &&
          connectTimeout == other.connectTimeout &&
          sendTimeout == other.sendTimeout &&
          receiveTimeout == other.receiveTimeout;

  @override
  int get hashCode =>
      Object.hash(connectTimeout, sendTimeout, receiveTimeout);

  @override
  String toString() => 'TimeoutConfig('
      'connect: $connectTimeout, '
      'send: $sendTimeout, '
      'receive: $receiveTimeout)';
}
