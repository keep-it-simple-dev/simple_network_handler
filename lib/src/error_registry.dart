import 'package:dio/dio.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:simple_network_handler/src/retry_config.dart';
import 'package:simple_network_handler/src/timeout_config.dart';

typedef EitherFactory = Either<Failure, dynamic> Function(
    Map<String, dynamic> json);
typedef ErrorModelRegistry = Map<String, Map<int, EitherFactory>>;
typedef DioErrorRegistry = Map<DioExceptionType, Failure>;
typedef GeneralErrorRegistry = Map<Type, Failure Function(Object exception)>;
typedef RetryRegistry = Map<String, RetryConfig>;
typedef TimeoutRegistry = Map<String, TimeoutConfig>;

/// Abstract error registry that can be implemented by different projects
abstract class ErrorRegistry {
  /// Returns the endpoint-specific error mappings
  ErrorModelRegistry get endpointRegistry;

  /// Returns the key for all endpoints
  String get allEndpointsKey => '*';

  /// Returns the key for parsing the either from the response
  String get parsedEitherKey => 'parsedEither';

  /// Returns the default failure for unhandled cases
  Failure get genericError;

  /// Returns the mapping for Dio exception types to failures
  DioErrorRegistry get dioRegistry;

  /// Returns the mapping for general exception types to failures
  GeneralErrorRegistry get generalRegistry;

  // ===== Phase 1: Retry Configuration =====

  /// Default retry configuration for all requests
  /// Override to enable global retry behavior
  /// Returns null by default (no retry)
  RetryConfig? get defaultRetryConfig => null;

  /// Endpoint-specific retry configuration
  /// Key is endpoint path, use [allEndpointsKey] ('*') for global override
  /// Endpoint-specific config takes precedence over [defaultRetryConfig]
  RetryRegistry get retryRegistry => const {};

  /// Get effective retry config for a specific endpoint
  /// Resolution order: endpoint-specific > allEndpointsKey > defaultRetryConfig
  RetryConfig? getRetryConfigForEndpoint(String path) {
    return retryRegistry[path] ??
        retryRegistry[allEndpointsKey] ??
        defaultRetryConfig;
  }

  /// Global callback invoked before each retry attempt
  /// Override to add centralized logging or metrics
  void Function(int attempt, Duration delay, Object error)? get onRetry => null;

  // ===== Phase 1: Timeout Configuration =====

  /// Default timeout configuration for all requests
  /// Override to set global timeout behavior
  /// Returns null by default (use Dio defaults)
  TimeoutConfig? get defaultTimeoutConfig => null;

  /// Endpoint-specific timeout configuration
  /// Key is endpoint path, use [allEndpointsKey] ('*') for global override
  /// Endpoint-specific config takes precedence over [defaultTimeoutConfig]
  TimeoutRegistry get timeoutRegistry => const {};

  /// Get effective timeout config for a specific endpoint
  /// Resolution order: endpoint-specific > allEndpointsKey > defaultTimeoutConfig
  TimeoutConfig? getTimeoutConfigForEndpoint(String path) {
    return timeoutRegistry[path] ??
        timeoutRegistry[allEndpointsKey] ??
        defaultTimeoutConfig;
  }

  /// Default operation timeout (total time including all retries)
  /// Returns null by default (no operation timeout)
  Duration? get defaultOperationTimeout => null;

  // ===== Phase 1: Cancellation Configuration =====

  /// Factory for creating cancellation failures
  /// Override to use a custom CancellationFailure subclass
  Failure createCancellationFailure([String? reason]) =>
      CancellationFailure(reason: reason);
}
