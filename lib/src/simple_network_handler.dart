import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:simple_network_handler/src/call_options.dart';
import 'package:simple_network_handler/src/retry_config.dart';

class SimpleNetworkHandler {
  static ErrorRegistry? _errorRegistry;
  static bool _enableDebugLogging = false;

  static void setErrorRegistry(ErrorRegistry registry) {
    _errorRegistry = registry;
  }

  static void setDebugLogging(bool enabled) {
    _enableDebugLogging = enabled;
  }

  /// Get the current error registry (for testing/debugging)
  static ErrorRegistry? get errorRegistry => _errorRegistry;

  static void _logError(Object error, StackTrace stackTrace) {
    if (_enableDebugLogging) {
      debugPrint('SimpleNetworkHandler Error: $error');
      debugPrint('Stack trace:\n$stackTrace');
    }
  }

  static void _logRetry(int attempt, Duration delay, Object error) {
    if (_enableDebugLogging) {
      debugPrint(
          'SimpleNetworkHandler Retry: attempt $attempt, delay ${delay.inMilliseconds}ms');
      debugPrint('SimpleNetworkHandler Retry reason: $error');
    }
  }

  /// Execute a network request with automatic error handling, retry, and cancellation support
  ///
  /// [request] - The async function that performs the network call
  /// [onEndpointError] - Optional endpoint-specific error handler (legacy support)
  /// [options] - Configuration for retry, timeout, and cancellation (overrides registry defaults)
  /// [endpointPath] - Optional endpoint path for looking up registry configuration
  ///                  If not provided, registry defaults are used
  ///
  /// Returns Either<Failure, T> where:
  /// - Left(Failure) on any error (network, timeout, cancellation, etc.)
  /// - Right(T) on successful response
  static Future<Either<Failure, T>> safeCall<T>(
    Future<T> Function() request, {
    Either<Failure, T>? Function(DioException)? onEndpointError,
    CallOptions? options,
    String? endpointPath,
  }) async {
    assert(_errorRegistry != null,
        'Error registry must be set before calling safeNetworkCall');

    final registry = _errorRegistry!;

    // Resolve effective retry configuration
    // Priority: CallOptions > Registry endpoint-specific > Registry default
    final RetryConfig? retryConfig = options?.retry ??
        (endpointPath != null
            ? registry.getRetryConfigForEndpoint(endpointPath)
            : registry.defaultRetryConfig);

    // Resolve operation timeout
    final Duration? operationTimeout =
        options?.operationTimeout ?? registry.defaultOperationTimeout;

    // Get cancel token from options
    final cancelToken = options?.cancelToken;

    int attempt = 0;
    final stopwatch = operationTimeout != null ? (Stopwatch()..start()) : null;

    while (true) {
      // Check operation timeout before each attempt
      if (stopwatch != null && stopwatch.elapsed >= operationTimeout!) {
        _logError('Operation timeout exceeded', StackTrace.current);
        return Left(registry.genericError);
      }

      // Check for cancellation before each attempt
      if (cancelToken?.isCancelled ?? false) {
        return Left(registry.createCancellationFailure(
            cancelToken?.cancelError?.message));
      }

      try {
        final result = await request();
        return Right(result);
      } on DioException catch (e, stackTrace) {
        _logError(e, stackTrace);

        // Handle cancellation specifically
        if (e.type == DioExceptionType.cancel) {
          return Left(registry.createCancellationFailure(e.message));
        }

        // Check if we should retry
        if (retryConfig != null &&
            !retryConfig.isDisabled &&
            retryConfig.shouldRetry(e, attempt)) {
          final delay = retryConfig.getDelayForAttempt(attempt);

          _logRetry(attempt + 1, delay, e);

          // Call registry onRetry callback
          registry.onRetry?.call(attempt + 1, delay, e);

          // Call config-level onRetry callback
          retryConfig.onRetry?.call(attempt + 1, delay, e);

          // Call per-call onRetry callback
          options?.onRetry?.call(attempt + 1, delay, e);

          await Future.delayed(delay);
          attempt++;
          continue; // Retry the request
        }

        // No retry - proceed with error handling
        return _handleDioError<T>(e, onEndpointError, registry);
      } catch (e, stackTrace) {
        _logError(e, stackTrace);

        // Check if we should retry non-Dio exceptions
        if (retryConfig != null &&
            !retryConfig.isDisabled &&
            retryConfig.shouldRetry(e, attempt)) {
          final delay = retryConfig.getDelayForAttempt(attempt);

          _logRetry(attempt + 1, delay, e);

          // Call retry callbacks
          registry.onRetry?.call(attempt + 1, delay, e);
          retryConfig.onRetry?.call(attempt + 1, delay, e);
          options?.onRetry?.call(attempt + 1, delay, e);

          await Future.delayed(delay);
          attempt++;
          continue;
        }

        // No retry - proceed with error handling
        return _handleGeneralError<T>(e, registry);
      }
    }
  }

  /// Handle DioException and map to appropriate Failure
  static Either<Failure, T> _handleDioError<T>(
    DioException e,
    Either<Failure, T>? Function(DioException)? onEndpointError,
    ErrorRegistry registry,
  ) {
    // Check for pre-parsed Either in response.extra (from interceptor)
    final dynamic parsedEither = e.response?.extra[registry.parsedEitherKey];
    if (parsedEither is Either<Failure, dynamic>) {
      return parsedEither.fold(
        (failure) => Left<Failure, T>(failure),
        (success) => Right<Failure, T>(success as T),
      );
    }

    // Endpoint-specific error handling (legacy callback)
    if (onEndpointError != null) {
      final endpointFailure = onEndpointError(e);
      if (endpointFailure != null) {
        return endpointFailure;
      }
    }

    // Handle specific network error types using registry
    final dioFailure = registry.dioRegistry[e.type];
    if (dioFailure != null) {
      return Left(dioFailure);
    }

    // Fallback to generic error
    return Left(registry.genericError);
  }

  /// Handle general exceptions and map to appropriate Failure
  static Either<Failure, T> _handleGeneralError<T>(
    Object e,
    ErrorRegistry registry,
  ) {
    // Handle custom exceptions using general error registry
    final failureFactory = registry.generalRegistry[e.runtimeType];
    if (failureFactory != null) {
      return Left(failureFactory(e));
    }

    // Fallback to generic error for unhandled exceptions
    return Left(registry.genericError);
  }
}
