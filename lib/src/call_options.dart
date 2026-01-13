import 'package:dio/dio.dart';
import 'package:simple_network_handler/src/retry_config.dart';
import 'package:simple_network_handler/src/timeout_config.dart';

/// Options for a single safeCall invocation
/// Merges with registry defaults - per-call values take precedence
class CallOptions {
  /// Retry configuration for this call
  /// - null: use registry default
  /// - RetryConfig.disabled: explicitly disable retry for this call
  /// - RetryConfig(...): custom config for this call
  final RetryConfig? retry;

  /// Cancel token for this call
  final CancelToken? cancelToken;

  /// Timeout configuration for this call
  /// - null: use registry default
  /// - TimeoutConfig(...): custom config for this call
  final TimeoutConfig? timeout;

  /// Overall timeout for the entire operation (including retries)
  /// - null: use registry default
  /// - Duration: custom timeout for this call
  final Duration? operationTimeout;

  /// Per-call retry callback (called in addition to registry onRetry)
  final void Function(int attempt, Duration delay, Object error)? onRetry;

  const CallOptions({
    this.retry,
    this.cancelToken,
    this.timeout,
    this.operationTimeout,
    this.onRetry,
  });

  /// Disable retry for this call (even if registry default is enabled)
  factory CallOptions.noRetry({CancelToken? cancelToken}) =>
      CallOptions(retry: RetryConfig.disabled, cancelToken: cancelToken);

  /// Create options with just retry config
  factory CallOptions.withRetry(RetryConfig retry, {CancelToken? cancelToken}) =>
      CallOptions(retry: retry, cancelToken: cancelToken);

  /// Create options with just timeout
  factory CallOptions.withTimeout(TimeoutConfig timeout,
          {CancelToken? cancelToken}) =>
      CallOptions(timeout: timeout, cancelToken: cancelToken);

  /// Create options with cancel token only
  factory CallOptions.cancellable(CancelToken cancelToken) =>
      CallOptions(cancelToken: cancelToken);

  @override
  String toString() => 'CallOptions('
      'retry: $retry, '
      'cancelToken: ${cancelToken != null ? "set" : "null"}, '
      'timeout: $timeout, '
      'operationTimeout: $operationTimeout)';
}
