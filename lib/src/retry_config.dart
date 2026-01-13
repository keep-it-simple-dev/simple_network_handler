import 'dart:math';

import 'package:dio/dio.dart';

/// Configuration for automatic retry behavior
class RetryConfig {
  /// Maximum number of retry attempts (excluding initial request)
  /// Total attempts = 1 (initial) + maxAttempts (retries)
  final int maxAttempts;

  /// Initial delay before first retry
  final Duration initialDelay;

  /// Multiplier applied to delay after each attempt (for exponential backoff)
  /// delay = initialDelay * (backoffMultiplier ^ attemptNumber)
  final double backoffMultiplier;

  /// Maximum delay between retries (caps the exponential growth)
  final Duration? maxDelay;

  /// Add random jitter to prevent thundering herd
  /// Jitter adds 0-50% additional random delay
  final bool useJitter;

  /// HTTP status codes that should trigger a retry
  /// Default: 408, 429, 500, 502, 503, 504
  final Set<int> retryStatusCodes;

  /// Dio exception types that should trigger a retry
  /// Default: connectionTimeout, sendTimeout, receiveTimeout, connectionError
  final Set<DioExceptionType> retryExceptionTypes;

  /// Custom predicate for retry decisions
  /// If provided, takes precedence over status code and exception type checks
  /// Parameters: error object, current attempt number (0-indexed)
  final bool Function(Object error, int attempt)? retryWhen;

  /// Callback invoked before each retry attempt
  /// Useful for logging, metrics, or user notification
  /// Parameters: attempt number (1-indexed), delay before retry, error that caused retry
  final void Function(int attempt, Duration delay, Object error)? onRetry;

  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.useJitter = true,
    this.retryStatusCodes = const {408, 429, 500, 502, 503, 504},
    this.retryExceptionTypes = const {
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    },
    this.retryWhen,
    this.onRetry,
  });

  /// Explicitly disabled retry - use to override registry defaults
  static const disabled = RetryConfig(maxAttempts: 0);

  /// Check if retry is disabled
  bool get isDisabled => maxAttempts <= 0;

  /// Preset for aggressive retry (more attempts, shorter delays)
  factory RetryConfig.aggressive() => const RetryConfig(
        maxAttempts: 5,
        initialDelay: Duration(milliseconds: 500),
        backoffMultiplier: 1.5,
        maxDelay: Duration(seconds: 10),
      );

  /// Preset for conservative retry (fewer attempts, longer delays)
  factory RetryConfig.conservative() => const RetryConfig(
        maxAttempts: 2,
        initialDelay: Duration(seconds: 2),
        backoffMultiplier: 3.0,
        maxDelay: Duration(seconds: 60),
      );

  /// Calculate delay for a given attempt number (0-indexed)
  Duration getDelayForAttempt(int attempt, [Random? random]) {
    // Calculate exponential delay
    final baseDelayMs =
        initialDelay.inMilliseconds * pow(backoffMultiplier, attempt);
    var delayMs = baseDelayMs.toInt();

    // Apply max delay cap
    if (maxDelay != null && delayMs > maxDelay!.inMilliseconds) {
      delayMs = maxDelay!.inMilliseconds;
    }

    // Apply jitter (0-50% additional random delay)
    if (useJitter) {
      final rng = random ?? Random();
      final jitterFactor = 1.0 + rng.nextDouble() * 0.5;
      delayMs = (delayMs * jitterFactor).toInt();
    }

    return Duration(milliseconds: delayMs);
  }

  /// Determine if an error should trigger a retry
  bool shouldRetry(Object error, int attempt) {
    // Check attempt count first
    if (attempt >= maxAttempts) {
      return false;
    }

    // Use custom predicate if provided
    if (retryWhen != null) {
      return retryWhen!(error, attempt);
    }

    // Check DioException
    if (error is DioException) {
      // Check exception type
      if (retryExceptionTypes.contains(error.type)) {
        return true;
      }

      // Check status code
      final statusCode = error.response?.statusCode;
      if (statusCode != null && retryStatusCodes.contains(statusCode)) {
        return true;
      }
    }

    return false;
  }

  /// Merge with another config (other takes precedence for non-null values)
  /// Note: callbacks are not merged, other's callback replaces this one
  RetryConfig mergeWith(RetryConfig? other) {
    if (other == null) return this;
    return RetryConfig(
      maxAttempts: other.maxAttempts,
      initialDelay: other.initialDelay,
      backoffMultiplier: other.backoffMultiplier,
      maxDelay: other.maxDelay ?? maxDelay,
      useJitter: other.useJitter,
      retryStatusCodes: other.retryStatusCodes,
      retryExceptionTypes: other.retryExceptionTypes,
      retryWhen: other.retryWhen ?? retryWhen,
      onRetry: other.onRetry ?? onRetry,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetryConfig &&
          runtimeType == other.runtimeType &&
          maxAttempts == other.maxAttempts &&
          initialDelay == other.initialDelay &&
          backoffMultiplier == other.backoffMultiplier &&
          maxDelay == other.maxDelay &&
          useJitter == other.useJitter;

  @override
  int get hashCode => Object.hash(
        maxAttempts,
        initialDelay,
        backoffMultiplier,
        maxDelay,
        useJitter,
      );

  @override
  String toString() => 'RetryConfig('
      'maxAttempts: $maxAttempts, '
      'initialDelay: $initialDelay, '
      'backoff: $backoffMultiplier, '
      'maxDelay: $maxDelay, '
      'jitter: $useJitter)';
}
