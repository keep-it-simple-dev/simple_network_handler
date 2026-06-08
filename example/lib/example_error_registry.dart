import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:simple_network_handler_example/network/example_api.dart';
import 'package:simple_network_handler_example/models/example_failure.dart';

/// Example error registry for getUserById endpoint
/// Demonstrates Phase 1 features: retry, timeout, and cancellation configuration
class ExampleErrorRegistry extends ErrorRegistry {
  @override
  ErrorModelRegistry get endpointRegistry => {
    // Global error mappings
    '*': {500: (json) => Left(ServerFailure())},

    // Specific mapping for getUserById
    ExampleApiPath.getUserById: {
      404: (json) => const Left(UserNotFoundFailure()),
    },
  };

  @override
  Failure get genericError => const GenericFailure();

  @override
  DioErrorRegistry get dioRegistry => {
    DioExceptionType.connectionError: const NoInternetFailure(),
    DioExceptionType.connectionTimeout: const TimeoutFailure(),
    DioExceptionType.receiveTimeout: const TimeoutFailure(),
    DioExceptionType.sendTimeout: const TimeoutFailure(),
  };

  @override
  GeneralErrorRegistry get generalRegistry => {
    FormatException: (e) => const GenericFailure(),
    TypeError: (_) => const GenericFailure(),
  };

  // ===== Phase 1: Retry Configuration =====

  /// Default retry configuration for all requests
  /// Retries up to 3 times on transient failures with exponential backoff
  @override
  RetryConfig? get defaultRetryConfig => const RetryConfig(
        maxAttempts: 3,
        initialDelay: Duration(seconds: 1),
        backoffMultiplier: 2.0,
        maxDelay: Duration(seconds: 10),
        useJitter: true,
        // Default retry on: 408, 429, 500, 502, 503, 504
        // Default retry on: connectionTimeout, sendTimeout, receiveTimeout, connectionError
      );

  /// Endpoint-specific retry configuration
  /// Override default retry for specific endpoints
  @override
  RetryRegistry get retryRegistry => {
    // More aggressive retry for critical user data
    ExampleApiPath.getUserById: const RetryConfig(
      maxAttempts: 5,
      initialDelay: Duration(milliseconds: 500),
      backoffMultiplier: 1.5,
    ),
    // Example: disable retry for non-idempotent endpoints
    // '/api/payment': RetryConfig.disabled,
  };

  /// Global retry callback for logging/metrics
  @override
  void Function(int attempt, Duration delay, Object error)? get onRetry =>
      (attempt, delay, error) {
        if (kDebugMode) {
          debugPrint(
              'Retry attempt $attempt, waiting ${delay.inMilliseconds}ms');
          debugPrint('Error: $error');
        }
      };

  // ===== Phase 1: Timeout Configuration =====

  /// Default timeout configuration for all requests
  @override
  TimeoutConfig? get defaultTimeoutConfig => TimeoutConfig.standard;

  /// Endpoint-specific timeout configuration
  @override
  TimeoutRegistry get timeoutRegistry => {
    // Quick timeout for user lookup
    ExampleApiPath.getUserById: TimeoutConfig.quick,
    // Example: longer timeout for file uploads
    // '/api/upload': TimeoutConfig.longRunning,
  };

  /// Default operation timeout (total time including all retries)
  @override
  Duration? get defaultOperationTimeout => const Duration(minutes: 2);
}
