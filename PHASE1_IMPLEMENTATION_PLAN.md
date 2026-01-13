# Phase 1 Implementation Plan

## Overview

Phase 1 focuses on **Core Reliability** features:
1. **Retry Mechanism** - Automatic retry with exponential backoff
2. **Request Cancellation** - CancelToken support with dedicated failure type
3. **Timeout Configuration** - Configurable timeouts at multiple levels
4. **Global Configuration** - Set defaults once, override per-call when needed

---

## Design Principle: ErrorRegistry Defaults + Per-Call Overrides

All Phase 1 features support a **two-level configuration** approach via ErrorRegistry:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Configuration Hierarchy                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   1. Global Defaults (via ErrorRegistry properties)             │
│      └── defaultRetryConfig, defaultTimeoutConfig, etc.         │
│                                                                  │
│   2. Endpoint-Specific (via ErrorRegistry registries)           │
│      └── retryRegistry, timeoutRegistry per endpoint            │
│                                                                  │
│   3. Per-Call Overrides (optional, for specific requests)       │
│      └── safeCall(..., options: CallOptions(...))               │
│                                                                  │
│   Resolution: Per-call > Endpoint-specific > Global defaults    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Example:**
```dart
// In ErrorRegistry - set global and endpoint-specific defaults
class MyErrorRegistry extends ErrorRegistry {
  @override
  RetryConfig? get defaultRetryConfig => const RetryConfig(maxAttempts: 3);

  @override
  TimeoutConfig? get defaultTimeoutConfig => TimeoutConfig.standard;

  @override
  Map<String, RetryConfig> get retryRegistry => {
    '/api/upload': RetryConfig.conservative(),  // Different retry for uploads
    '/api/payment': RetryConfig.disabled,       // No retry for payments
  };
}

// In repository - uses registry defaults automatically
final result = await SimpleNetworkHandler.safeCall(
  () => api.getProducts(),
);

// For specific call - override timeout only, keep registry retry
final result = await SimpleNetworkHandler.safeCall(
  () => api.uploadLargeFile(file),
  options: CallOptions(timeout: TimeoutConfig.longRunning),
);

// For specific call - disable retry entirely
final result = await SimpleNetworkHandler.safeCall(
  () => api.sendOneTimeToken(),
  options: CallOptions(retry: RetryConfig.disabled),
);
```

---

## Current Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Code                                 │
│   repository.getData() → SimpleNetworkHandler.safeCall()        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SimpleNetworkHandler                          │
│   - Wraps request in try/catch                                   │
│   - Checks for pre-parsed Either in response.extra               │
│   - Maps DioException via dioRegistry                            │
│   - Maps custom exceptions via generalRegistry                   │
│   - Returns Either<Failure, T>                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Dio + Interceptor                             │
│   - ErrorMappingInterceptor attaches parsed Either               │
│   - Uses ErrorRegistry for endpoint/status code mapping          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. Retry Mechanism

### Design Goals
- Zero breaking changes to existing API
- Configurable via optional parameter
- Support exponential backoff with jitter
- Allow filtering which errors trigger retry
- Provide hooks for observability

### New Files

#### `lib/src/retry_config.dart`

```dart
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
  final Set<DioExceptionType> retryDioExceptionTypes;

  /// Custom predicate for retry decisions
  /// If provided, takes precedence over status code and exception type checks
  final bool Function(Object error, int attempt)? retryWhen;

  /// Callback invoked before each retry attempt
  /// Useful for logging, metrics, or user notification
  final void Function(int attempt, Duration delay, Object error)? onRetry;

  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.useJitter = true,
    this.retryStatusCodes = const {408, 429, 500, 502, 503, 504},
    this.retryDioExceptionTypes = const {
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    },
    this.retryWhen,
    this.onRetry,
  });

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
  Duration getDelayForAttempt(int attempt) {
    // Calculate exponential delay
    var delay = initialDelay * pow(backoffMultiplier, attempt);

    // Apply max delay cap
    if (maxDelay != null && delay > maxDelay!) {
      delay = maxDelay!;
    }

    // Apply jitter (0-50% additional random delay)
    if (useJitter) {
      final jitterFactor = 1.0 + Random().nextDouble() * 0.5;
      delay = delay * jitterFactor;
    }

    return delay;
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
      if (retryDioExceptionTypes.contains(error.type)) {
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
}
```

### Changes to `simple_network_handler.dart`

```dart
static Future<Either<Failure, T>> safeCall<T>(
  Future<T> Function() request, {
  Either<Failure, T>? Function(DioException)? onEndpointError,
  RetryConfig? retry,                    // NEW
  CancelToken? cancelToken,              // NEW (for feature 2)
}) async {
  assert(_errorRegistry != null,
      'Error registry must be set before calling safeNetworkCall');

  int attempt = 0;

  while (true) {
    try {
      // Check for cancellation before each attempt
      if (cancelToken?.isCancelled ?? false) {
        return Left(_createCancellationFailure());
      }

      final result = await request();
      return Right(result);

    } on DioException catch (e, stackTrace) {
      _logError(e, stackTrace);

      // Handle cancellation specifically
      if (e.type == DioExceptionType.cancel) {
        return Left(_createCancellationFailure());
      }

      // Check if we should retry
      if (retry != null && retry.shouldRetry(e, attempt)) {
        final delay = retry.getDelayForAttempt(attempt);
        retry.onRetry?.call(attempt + 1, delay, e);
        await Future.delayed(delay);
        attempt++;
        continue; // Retry the request
      }

      // No retry - proceed with error handling
      // [existing error handling logic unchanged]

    } catch (e, stackTrace) {
      _logError(e, stackTrace);

      // Check if we should retry non-Dio exceptions
      if (retry != null && retry.shouldRetry(e, attempt)) {
        final delay = retry.getDelayForAttempt(attempt);
        retry.onRetry?.call(attempt + 1, delay, e);
        await Future.delayed(delay);
        attempt++;
        continue;
      }

      // [existing error handling logic unchanged]
    }
  }
}
```

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      safeCall() with RetryConfig                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  attempt = 0    │
                    └─────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │      Execute request()         │◄─────────────┐
              └───────────────────────────────┘               │
                              │                               │
                    ┌─────────┴─────────┐                     │
                    ▼                   ▼                     │
              ┌──────────┐        ┌──────────┐                │
              │ Success  │        │  Error   │                │
              └──────────┘        └──────────┘                │
                    │                   │                     │
                    ▼                   ▼                     │
              ┌──────────┐   ┌─────────────────────┐          │
              │ Right(T) │   │ shouldRetry(error)? │          │
              └──────────┘   └─────────────────────┘          │
                                  │           │               │
                              yes │           │ no            │
                                  ▼           ▼               │
                          ┌───────────┐  ┌────────────┐       │
                          │ onRetry() │  │ Map error  │       │
                          │ delay()   │  │ to Failure │       │
                          │ attempt++ │  └────────────┘       │
                          └───────────┘        │              │
                                  │            ▼              │
                                  │     ┌─────────────┐       │
                                  └────►│ Left(Fail)  │       │
                                        └─────────────┘       │
```

---

## 2. Request Cancellation

### Design Goals
- Leverage Dio's existing CancelToken mechanism
- Provide a dedicated `CancellationFailure` type
- Allow graceful handling of user-initiated cancellations

### New Files

#### `lib/src/cancellation_failure.dart`

```dart
import 'package:flutter/material.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

/// Failure type returned when a request is cancelled
class CancellationFailure extends Failure {
  /// Optional reason for cancellation
  final String? reason;

  const CancellationFailure({this.reason});

  @override
  String getTitle(BuildContext context) => 'Request Cancelled';

  @override
  String getSubtitle(BuildContext context) =>
      reason ?? 'The operation was cancelled';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CancellationFailure && reason == other.reason;

  @override
  int get hashCode => reason.hashCode;
}
```

### Changes to `simple_network_handler.dart`

```dart
import 'package:dio/dio.dart';

class SimpleNetworkHandler {
  // ... existing code ...

  /// Factory for creating cancellation failures
  /// Can be overridden via setCancellationFailureFactory()
  static Failure Function(String? reason)? _cancellationFailureFactory;

  /// Set a custom factory for cancellation failures
  static void setCancellationFailureFactory(
    Failure Function(String? reason) factory,
  ) {
    _cancellationFailureFactory = factory;
  }

  static Failure _createCancellationFailure([String? reason]) {
    if (_cancellationFailureFactory != null) {
      return _cancellationFailureFactory!(reason);
    }
    return CancellationFailure(reason: reason);
  }

  static Future<Either<Failure, T>> safeCall<T>(
    Future<T> Function() request, {
    Either<Failure, T>? Function(DioException)? onEndpointError,
    RetryConfig? retry,
    CancelToken? cancelToken,  // NEW PARAMETER
  }) async {
    // ... implementation with cancellation check ...
  }
}
```

### Usage Example

```dart
class MyRepository {
  CancelToken? _currentToken;

  Future<Either<Failure, User>> getUser(int id) {
    // Cancel any previous request
    _currentToken?.cancel('New request started');
    _currentToken = CancelToken();

    return SimpleNetworkHandler.safeCall(
      () => _api.getUser(id, cancelToken: _currentToken),
      cancelToken: _currentToken,
    );
  }

  void dispose() {
    _currentToken?.cancel('Repository disposed');
  }
}
```

### Handling in UI

```dart
result.fold(
  (failure) {
    if (failure is CancellationFailure) {
      // Don't show error for user-initiated cancellation
      return;
    }
    showErrorDialog(failure);
  },
  (data) => updateUI(data),
);
```

---

## 3. Timeout Configuration

### Design Goals
- Provide per-call timeout configuration
- Support registry-based default timeouts per endpoint
- Separate connect, send, and receive timeouts
- Integrate with retry mechanism (overall operation timeout)

### New Files

#### `lib/src/timeout_config.dart`

```dart
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

  /// Merge with another config (other takes precedence)
  TimeoutConfig merge(TimeoutConfig? other) {
    if (other == null) return this;
    return TimeoutConfig(
      connectTimeout: other.connectTimeout ?? connectTimeout,
      sendTimeout: other.sendTimeout ?? sendTimeout,
      receiveTimeout: other.receiveTimeout ?? receiveTimeout,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeoutConfig &&
          connectTimeout == other.connectTimeout &&
          sendTimeout == other.sendTimeout &&
          receiveTimeout == other.receiveTimeout;

  @override
  int get hashCode => Object.hash(connectTimeout, sendTimeout, receiveTimeout);
}
```

#### `lib/src/call_options.dart`

```dart
import 'package:dio/dio.dart';
import 'timeout_config.dart';
import 'retry_config.dart';

/// Options for a single safeCall invocation
/// Consolidates all optional parameters for cleaner API
class CallOptions {
  /// Retry configuration for this call
  final RetryConfig? retry;

  /// Cancel token for this call
  final CancelToken? cancelToken;

  /// Timeout configuration for this call
  final TimeoutConfig? timeout;

  /// Overall timeout for the entire operation (including retries)
  /// If exceeded, returns TimeoutFailure regardless of retry config
  final Duration? operationTimeout;

  const CallOptions({
    this.retry,
    this.cancelToken,
    this.timeout,
    this.operationTimeout,
  });

  /// Create options with just retry config
  factory CallOptions.withRetry(RetryConfig retry) =>
      CallOptions(retry: retry);

  /// Create options with just timeout
  factory CallOptions.withTimeout(TimeoutConfig timeout) =>
      CallOptions(timeout: timeout);
}
```

### Changes to `error_registry.dart`

```dart
import 'timeout_config.dart';

typedef TimeoutRegistry = Map<String, TimeoutConfig>;

abstract class ErrorRegistry {
  // ... existing properties ...

  /// Returns timeout configuration per endpoint
  /// Key is endpoint path, '*' for global default
  /// Override to provide custom timeout settings
  TimeoutRegistry get timeoutRegistry => const {};

  /// Get timeout config for a specific endpoint
  TimeoutConfig? getTimeoutForEndpoint(String path) {
    return timeoutRegistry[path] ?? timeoutRegistry[allEndpointsKey];
  }
}
```

### Timeout Application Strategy

Since `safeCall()` receives a `Future<T> Function()` without direct access to Dio options, we have two approaches:

#### Approach A: Wrapper Helper (Recommended)

Provide a helper that users wrap their API calls with:

```dart
// In repository
Future<Either<Failure, User>> getUser(int id) {
  return SimpleNetworkHandler.safeCall(
    () => _api.getUser(id).timeout(Duration(seconds: 10)),
    options: CallOptions(
      timeout: TimeoutConfig.quick,
      operationTimeout: Duration(seconds: 30),
    ),
  );
}
```

#### Approach B: Dio Interceptor Enhancement

Add timeout application in the interceptor:

```dart
class ErrorMappingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    final timeoutConfig = errorRegistry.getTimeoutForEndpoint(path);

    if (timeoutConfig != null) {
      options.connectTimeout = timeoutConfig.connectTimeout;
      options.sendTimeout = timeoutConfig.sendTimeout;
      options.receiveTimeout = timeoutConfig.receiveTimeout;
    }

    handler.next(options);
  }

  // ... existing onResponse and onError ...
}
```

### Operation Timeout

The `operationTimeout` in `CallOptions` limits the total time including retries:

```dart
static Future<Either<Failure, T>> safeCall<T>(
  Future<T> Function() request, {
  CallOptions? options,
}) async {
  final stopwatch = Stopwatch()..start();

  while (true) {
    // Check operation timeout
    if (options?.operationTimeout != null &&
        stopwatch.elapsed >= options!.operationTimeout!) {
      return Left(_createTimeoutFailure('Operation timeout exceeded'));
    }

    try {
      final result = await request();
      return Right(result);
    } catch (e) {
      // ... retry logic with timeout check ...
    }
  }
}
```

---

## 4. Global Configuration

### Design Goals
- Set retry, timeout, and other defaults once at app initialization
- Apply defaults automatically to all `safeCall()` invocations
- Allow per-call overrides that merge with globals
- Support disabling features per-call even when globally enabled
- Keep backward compatibility (no global config = current behavior)

### New Files

#### `lib/src/global_config.dart`

```dart
import 'retry_config.dart';
import 'timeout_config.dart';

/// Global configuration for SimpleNetworkHandler
/// Set once at app startup, applies to all safeCall() invocations
class GlobalConfig {
  /// Default retry configuration for all requests
  /// Set to null to disable retry globally (default)
  /// Set to RetryConfig.disabled to explicitly disable
  final RetryConfig? retry;

  /// Default timeout configuration for all requests
  final TimeoutConfig? timeout;

  /// Default operation timeout (total time including retries)
  final Duration? operationTimeout;

  /// Global callback invoked before each retry attempt
  /// Useful for centralized logging/metrics
  final void Function(int attempt, Duration delay, Object error)? onRetry;

  /// Global callback invoked when a request fails (after all retries)
  /// Useful for centralized error tracking
  final void Function(Object error, StackTrace? stackTrace)? onError;

  const GlobalConfig({
    this.retry,
    this.timeout,
    this.operationTimeout,
    this.onRetry,
    this.onError,
  });

  /// No configuration - all features disabled (default behavior)
  static const none = GlobalConfig();

  /// Standard production defaults
  factory GlobalConfig.standard() => GlobalConfig(
        retry: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(seconds: 1),
        ),
        timeout: TimeoutConfig.standard,
      );

  /// Aggressive retry for unreliable networks
  factory GlobalConfig.aggressive() => GlobalConfig(
        retry: RetryConfig.aggressive(),
        timeout: TimeoutConfig.quick,
      );

  /// Merge with per-call options (per-call takes precedence)
  GlobalConfig mergeWith(CallOptions? options) {
    if (options == null) return this;

    return GlobalConfig(
      retry: options.retry ?? retry,
      timeout: options.timeout ?? timeout,
      operationTimeout: options.operationTimeout ?? operationTimeout,
      onRetry: options.onRetry ?? onRetry,
      onError: onError, // Global only - not overridable per-call
    );
  }
}
```

#### Update `lib/src/retry_config.dart` - Add disabled preset

```dart
class RetryConfig {
  // ... existing fields ...

  /// Explicitly disabled retry - use to override global config
  static const disabled = RetryConfig(maxAttempts: 0);

  /// Check if retry is disabled
  bool get isDisabled => maxAttempts <= 0;

  // ... rest of implementation ...
}
```

#### Update `lib/src/call_options.dart` - Add merge support

```dart
import 'package:dio/dio.dart';
import 'timeout_config.dart';
import 'retry_config.dart';

/// Options for a single safeCall invocation
/// Merges with global config - per-call values take precedence
class CallOptions {
  /// Retry configuration for this call
  /// - null: use global default
  /// - RetryConfig.disabled: explicitly disable retry for this call
  /// - RetryConfig(...): custom config for this call
  final RetryConfig? retry;

  /// Cancel token for this call
  final CancelToken? cancelToken;

  /// Timeout configuration for this call
  /// - null: use global default
  /// - TimeoutConfig(...): custom config for this call
  final TimeoutConfig? timeout;

  /// Overall timeout for the entire operation (including retries)
  /// - null: use global default
  /// - Duration: custom timeout for this call
  final Duration? operationTimeout;

  /// Per-call retry callback (supplements global onRetry)
  final void Function(int attempt, Duration delay, Object error)? onRetry;

  const CallOptions({
    this.retry,
    this.cancelToken,
    this.timeout,
    this.operationTimeout,
    this.onRetry,
  });

  /// Disable retry for this call (even if globally enabled)
  factory CallOptions.noRetry() => CallOptions(retry: RetryConfig.disabled);

  /// Create options with just retry config
  factory CallOptions.withRetry(RetryConfig retry) => CallOptions(retry: retry);

  /// Create options with just timeout
  factory CallOptions.withTimeout(TimeoutConfig timeout) =>
      CallOptions(timeout: timeout);
}
```

### Changes to `simple_network_handler.dart`

```dart
class SimpleNetworkHandler {
  static ErrorRegistry? _errorRegistry;
  static bool _enableDebugLogging = false;
  static GlobalConfig _globalConfig = GlobalConfig.none;  // NEW

  // ... existing methods ...

  /// Set global configuration for all safeCall() invocations
  /// Call once at app startup
  static void setGlobalConfig(GlobalConfig config) {
    _globalConfig = config;
  }

  /// Get current global configuration (for testing/debugging)
  static GlobalConfig get globalConfig => _globalConfig;

  /// Reset to default configuration (mainly for testing)
  static void resetGlobalConfig() {
    _globalConfig = GlobalConfig.none;
  }

  static Future<Either<Failure, T>> safeCall<T>(
    Future<T> Function() request, {
    Either<Failure, T>? Function(DioException)? onEndpointError,
    CallOptions? options,
  }) async {
    assert(_errorRegistry != null,
        'Error registry must be set before calling safeNetworkCall');

    // Merge global config with per-call options
    final effectiveConfig = _globalConfig.mergeWith(options);
    final retryConfig = effectiveConfig.retry;
    final cancelToken = options?.cancelToken;

    int attempt = 0;
    final stopwatch = Stopwatch()..start();

    while (true) {
      // Check operation timeout
      if (effectiveConfig.operationTimeout != null &&
          stopwatch.elapsed >= effectiveConfig.operationTimeout!) {
        return Left(_createTimeoutFailure('Operation timeout exceeded'));
      }

      // Check for cancellation
      if (cancelToken?.isCancelled ?? false) {
        return Left(_createCancellationFailure());
      }

      try {
        final result = await request();
        return Right(result);

      } on DioException catch (e, stackTrace) {
        _logError(e, stackTrace);
        effectiveConfig.onError?.call(e, stackTrace);

        // Handle cancellation
        if (e.type == DioExceptionType.cancel) {
          return Left(_createCancellationFailure());
        }

        // Check if we should retry
        if (retryConfig != null &&
            !retryConfig.isDisabled &&
            retryConfig.shouldRetry(e, attempt)) {
          final delay = retryConfig.getDelayForAttempt(attempt);

          // Call both global and per-call onRetry callbacks
          effectiveConfig.onRetry?.call(attempt + 1, delay, e);
          options?.onRetry?.call(attempt + 1, delay, e);

          await Future.delayed(delay);
          attempt++;
          continue;
        }

        // No retry - proceed with error handling
        // [existing error handling logic]

      } catch (e, stackTrace) {
        _logError(e, stackTrace);
        effectiveConfig.onError?.call(e, stackTrace);

        // Check if we should retry
        if (retryConfig != null &&
            !retryConfig.isDisabled &&
            retryConfig.shouldRetry(e, attempt)) {
          final delay = retryConfig.getDelayForAttempt(attempt);
          effectiveConfig.onRetry?.call(attempt + 1, delay, e);
          options?.onRetry?.call(attempt + 1, delay, e);
          await Future.delayed(delay);
          attempt++;
          continue;
        }

        // [existing error handling logic]
      }
    }
  }
}
```

### Alternative: Configuration via ErrorRegistry

For users who prefer keeping all configuration in one place, extend `ErrorRegistry`:

```dart
abstract class ErrorRegistry {
  // ... existing properties ...

  /// Default retry configuration for all requests
  /// Override to enable global retry
  RetryConfig? get defaultRetryConfig => null;

  /// Default timeout configuration for all requests
  /// Override to set global timeouts
  TimeoutConfig? get defaultTimeoutConfig => null;

  /// Default operation timeout
  Duration? get defaultOperationTimeout => null;

  /// Endpoint-specific retry configuration
  /// Key is endpoint path, overrides defaultRetryConfig
  Map<String, RetryConfig> get retryRegistry => const {};

  /// Get effective retry config for an endpoint
  RetryConfig? getRetryConfigForEndpoint(String path) {
    return retryRegistry[path] ??
           retryRegistry[allEndpointsKey] ??
           defaultRetryConfig;
  }
}
```

**Usage with ErrorRegistry:**
```dart
class MyErrorRegistry extends ErrorRegistry {
  // ... existing error mappings ...

  @override
  RetryConfig? get defaultRetryConfig => const RetryConfig(maxAttempts: 3);

  @override
  TimeoutConfig? get defaultTimeoutConfig => TimeoutConfig.standard;

  @override
  Map<String, RetryConfig> get retryRegistry => {
    // Aggressive retry for critical endpoints
    '/api/payment': RetryConfig.aggressive(),
    // No retry for idempotency-sensitive endpoints
    '/api/charge': RetryConfig.disabled,
  };
}
```

### Configuration Resolution Order

```
┌─────────────────────────────────────────────────────────────────┐
│                    Resolution Priority (highest to lowest)       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   1. CallOptions parameter in safeCall()                        │
│      └── Explicit per-call override                              │
│                                                                  │
│   2. ErrorRegistry endpoint-specific (retryRegistry, etc.)      │
│      └── Per-endpoint defaults in registry                       │
│                                                                  │
│   3. GlobalConfig via setGlobalConfig()                         │
│      └── App-wide defaults                                       │
│                                                                  │
│   4. ErrorRegistry defaults (defaultRetryConfig, etc.)          │
│      └── Registry-level defaults                                 │
│                                                                  │
│   5. Package defaults (no retry, no timeout)                    │
│      └── Backward compatible behavior                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Complete Initialization Example

```dart
void main() async {
  // 1. Set up error registry (required, existing pattern)
  SimpleNetworkHandler.setErrorRegistry(MyErrorRegistry());

  // 2. Set up global config (optional, new pattern)
  SimpleNetworkHandler.setGlobalConfig(GlobalConfig(
    retry: const RetryConfig(
      maxAttempts: 3,
      initialDelay: Duration(seconds: 1),
      onRetry: _logRetry,
    ),
    timeout: TimeoutConfig.standard,
    operationTimeout: Duration(minutes: 2),
    onError: _trackError,
  ));

  // 3. Enable debug logging (optional, existing pattern)
  SimpleNetworkHandler.setDebugLogging(kDebugMode);

  runApp(MyApp());
}

void _logRetry(int attempt, Duration delay, Object error) {
  logger.info('Retry attempt $attempt after ${delay.inSeconds}s');
}

void _trackError(Object error, StackTrace? stackTrace) {
  crashlytics.recordError(error, stackTrace);
}
```

### Usage Patterns

#### Pattern 1: Global defaults only (most common)
```dart
// Setup once
SimpleNetworkHandler.setGlobalConfig(GlobalConfig.standard());

// Use everywhere - retry and timeout applied automatically
final result = await SimpleNetworkHandler.safeCall(() => api.getData());
```

#### Pattern 2: Global + per-call override
```dart
// Setup global defaults
SimpleNetworkHandler.setGlobalConfig(GlobalConfig.standard());

// Override for specific call
final result = await SimpleNetworkHandler.safeCall(
  () => api.uploadLargeFile(file),
  options: CallOptions(
    timeout: TimeoutConfig.longRunning,
    operationTimeout: Duration(minutes: 10),
  ),
);
```

#### Pattern 3: Global enabled, per-call disabled
```dart
// Setup global retry
SimpleNetworkHandler.setGlobalConfig(GlobalConfig(
  retry: RetryConfig(maxAttempts: 3),
));

// Disable retry for non-idempotent request
final result = await SimpleNetworkHandler.safeCall(
  () => api.processPayment(payment),
  options: CallOptions.noRetry(),
);
```

#### Pattern 4: No global config (backward compatible)
```dart
// Don't set global config - works like before
final result = await SimpleNetworkHandler.safeCall(() => api.getData());

// Explicitly enable retry for specific call
final result = await SimpleNetworkHandler.safeCall(
  () => api.getData(),
  options: CallOptions(retry: RetryConfig(maxAttempts: 3)),
);
```

---

## File Structure After Phase 1

```
lib/
├── simple_network_handler.dart          # Public exports (updated)
└── src/
    ├── failure.dart                     # Base Failure (unchanged)
    ├── cancellation_failure.dart        # NEW: Cancellation failure type
    ├── error_registry.dart              # ErrorRegistry (updated)
    ├── error_mapping_interceptor.dart   # Interceptor (updated)
    ├── simple_network_handler.dart      # Main handler (updated)
    ├── retry_config.dart                # NEW: Retry configuration
    ├── timeout_config.dart              # NEW: Timeout configuration
    ├── call_options.dart                # NEW: Per-call options
    └── global_config.dart               # NEW: Global configuration
```

---

## Updated Public API

### New Exports in `simple_network_handler.dart`

```dart
library;

export 'package:dartz/dartz.dart' show Either, Left, Right;

// Core
export 'src/failure.dart';
export 'src/cancellation_failure.dart';       // NEW
export 'src/error_registry.dart';
export 'src/error_mapping_interceptor.dart';
export 'src/simple_network_handler.dart';

// Configuration
export 'src/retry_config.dart';               // NEW
export 'src/timeout_config.dart';             // NEW
export 'src/call_options.dart';               // NEW
export 'src/global_config.dart';              // NEW
```

### Updated `safeCall` Signature

```dart
/// Execute a network request with automatic error handling
///
/// [request] - The async function that performs the network call
/// [onEndpointError] - Optional endpoint-specific error handler (legacy)
/// [options] - Configuration for retry, timeout, and cancellation
///
/// Returns Either<Failure, T> where:
/// - Left(Failure) on any error (network, timeout, cancellation, etc.)
/// - Right(T) on successful response
static Future<Either<Failure, T>> safeCall<T>(
  Future<T> Function() request, {
  Either<Failure, T>? Function(DioException)? onEndpointError,
  CallOptions? options,
}) async
```

---

## Usage Examples

### Basic Retry

```dart
final result = await SimpleNetworkHandler.safeCall(
  () => api.getProducts(),
  options: CallOptions(
    retry: RetryConfig(maxAttempts: 3),
  ),
);
```

### Retry with Logging

```dart
final result = await SimpleNetworkHandler.safeCall(
  () => api.getProducts(),
  options: CallOptions(
    retry: RetryConfig(
      maxAttempts: 3,
      onRetry: (attempt, delay, error) {
        logger.warn('Retry $attempt after ${delay.inSeconds}s: $error');
      },
    ),
  ),
);
```

### Cancellable Request

```dart
final cancelToken = CancelToken();

// Start request
final resultFuture = SimpleNetworkHandler.safeCall(
  () => api.searchProducts(query, cancelToken: cancelToken),
  options: CallOptions(cancelToken: cancelToken),
);

// Later, user types new query
cancelToken.cancel('New search started');
```

### With All Options

```dart
final result = await SimpleNetworkHandler.safeCall(
  () => api.uploadFile(file, cancelToken: token),
  options: CallOptions(
    cancelToken: token,
    timeout: TimeoutConfig.longRunning,
    operationTimeout: Duration(minutes: 5),
    retry: RetryConfig(
      maxAttempts: 2,
      retryStatusCodes: {500, 502, 503},
    ),
  ),
);
```

---

## Testing Strategy

### Unit Tests for RetryConfig

```dart
group('RetryConfig', () {
  test('calculates exponential backoff correctly', () {
    final config = RetryConfig(
      initialDelay: Duration(seconds: 1),
      backoffMultiplier: 2.0,
      useJitter: false,
    );

    expect(config.getDelayForAttempt(0), Duration(seconds: 1));
    expect(config.getDelayForAttempt(1), Duration(seconds: 2));
    expect(config.getDelayForAttempt(2), Duration(seconds: 4));
  });

  test('respects maxDelay cap', () {
    final config = RetryConfig(
      initialDelay: Duration(seconds: 10),
      backoffMultiplier: 10.0,
      maxDelay: Duration(seconds: 30),
      useJitter: false,
    );

    expect(config.getDelayForAttempt(5), Duration(seconds: 30));
  });

  test('shouldRetry returns false when maxAttempts exceeded', () {
    final config = RetryConfig(maxAttempts: 2);
    final error = DioException(
      type: DioExceptionType.connectionTimeout,
      requestOptions: RequestOptions(),
    );

    expect(config.shouldRetry(error, 0), true);
    expect(config.shouldRetry(error, 1), true);
    expect(config.shouldRetry(error, 2), false);
  });
});
```

### Integration Tests

```dart
group('SimpleNetworkHandler retry', () {
  test('retries on 500 error and succeeds on retry', () async {
    int callCount = 0;

    final result = await SimpleNetworkHandler.safeCall(
      () async {
        callCount++;
        if (callCount < 3) {
          throw DioException(
            type: DioExceptionType.badResponse,
            response: Response(
              statusCode: 500,
              requestOptions: RequestOptions(),
            ),
            requestOptions: RequestOptions(),
          );
        }
        return 'success';
      },
      options: CallOptions(
        retry: RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 10),
        ),
      ),
    );

    expect(result.isRight(), true);
    expect(callCount, 3);
  });

  test('returns failure after exhausting retries', () async {
    int callCount = 0;

    final result = await SimpleNetworkHandler.safeCall(
      () async {
        callCount++;
        throw DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: RequestOptions(),
        );
      },
      options: CallOptions(
        retry: RetryConfig(
          maxAttempts: 2,
          initialDelay: Duration(milliseconds: 10),
        ),
      ),
    );

    expect(result.isLeft(), true);
    expect(callCount, 3); // 1 initial + 2 retries
  });
});
```

---

## Migration Guide

### For Existing Users

Phase 1 is **fully backward compatible**. Existing code continues to work:

```dart
// This still works exactly as before
final result = await SimpleNetworkHandler.safeCall(
  () => api.getData(),
);
```

### Adopting New Features

```dart
// Opt-in to retry
final result = await SimpleNetworkHandler.safeCall(
  () => api.getData(),
  options: CallOptions(retry: RetryConfig()),
);
```

---

## Implementation Order

1. **Create `timeout_config.dart`** - No dependencies
2. **Create `retry_config.dart`** - No dependencies (include `disabled` preset)
3. **Create `cancellation_failure.dart`** - Depends on `failure.dart`
4. **Create `call_options.dart`** - Depends on retry and timeout configs
5. **Create `global_config.dart`** - Depends on retry, timeout, and call_options
6. **Update `error_registry.dart`** - Add timeout/retry registries
7. **Update `error_mapping_interceptor.dart`** - Add onRequest for timeouts
8. **Update `simple_network_handler.dart`** - Add global config, retry loop, cancellation
9. **Update exports** - Add new files to public API
10. **Add tests** - Unit and integration tests
11. **Update example** - Demonstrate new features with global config
12. **Update documentation** - README and CHANGELOG

---

## Estimated Complexity

| Component | Lines of Code | Complexity |
|-----------|---------------|------------|
| `retry_config.dart` | ~130 | Medium |
| `timeout_config.dart` | ~70 | Low |
| `cancellation_failure.dart` | ~25 | Low |
| `call_options.dart` | ~45 | Low |
| `global_config.dart` | ~80 | Low |
| `error_registry.dart` changes | ~30 | Low |
| `interceptor` changes | ~25 | Low |
| `simple_network_handler.dart` changes | ~80 | Medium |
| Tests | ~250 | Medium |
| **Total** | **~735** | **Medium** |

---

## Open Questions

1. **Default retry behavior**: Should there be a global default retry config, or always explicit?
   - **RESOLVED**: Support both via `GlobalConfig` - users can set defaults at startup, override per-call

2. **Retry on non-Dio exceptions**: Should general exceptions (from `generalRegistry`) be retryable?
   - Recommendation: Yes, via `retryWhen` callback for flexibility

3. **Cancellation in interceptor**: Should cancelled requests skip the interceptor entirely?
   - Recommendation: Yes, check cancellation in onRequest

4. **Timeout precedence**: If both CallOptions timeout and registry timeout are set, which wins?
   - **RESOLVED**: Per-call (CallOptions) > Endpoint-specific (Registry) > Global (GlobalConfig/Registry defaults)

5. **GlobalConfig vs ErrorRegistry**: Where should global defaults live?
   - **RESOLVED**: Support both approaches - `setGlobalConfig()` for simplicity, or override registry properties for centralized config
