# Missing Features Analysis

This document identifies important features that would enhance the Simple Network Handler package. All suggestions are backend-agnostic and focus on improving reliability, developer experience, and production-readiness.

---

## 1. Retry Mechanism

**Priority:** High

**Current State:** No automatic retry support for transient failures.

**Proposed Features:**
- Configurable retry count per endpoint or globally
- Exponential backoff strategy
- Jitter support to prevent thundering herd
- Retry only on specific status codes (e.g., 5xx, 429) or exception types
- Custom retry conditions via callback
- Retry event hooks for logging/metrics

**Example API:**
```dart
final result = await SimpleNetworkHandler.safeCall(
  () => api.getData(),
  retry: RetryConfig(
    maxAttempts: 3,
    backoff: ExponentialBackoff(initial: Duration(seconds: 1)),
    retryOn: [500, 502, 503, 504],
  ),
);
```

---

## 2. Request Cancellation

**Priority:** High

**Current State:** No built-in cancellation support.

**Proposed Features:**
- Accept `CancelToken` in `safeCall()`
- Return a dedicated `CancellationFailure` when cancelled
- Support for cancelling in-flight requests
- Integration with widget lifecycle (dispose patterns)

**Example API:**
```dart
final cancelToken = CancelToken();
final result = await SimpleNetworkHandler.safeCall(
  () => api.getData(cancelToken: cancelToken),
  cancelToken: cancelToken,
);

// Later...
cancelToken.cancel('User navigated away');
```

---

## 3. Timeout Configuration

**Priority:** High

**Current State:** Relies on Dio's global timeout settings.

**Proposed Features:**
- Per-endpoint timeout configuration in registry
- Separate connect, send, and receive timeouts
- Timeout override in `safeCall()` options
- Dedicated `TimeoutFailure` types for different timeout scenarios

**Example API:**
```dart
class MyErrorRegistry extends ErrorRegistry {
  @override
  Map<String, TimeoutConfig> get timeoutRegistry => {
    'getUserById': TimeoutConfig(
      connect: Duration(seconds: 5),
      receive: Duration(seconds: 30),
    ),
    '*': TimeoutConfig.defaultConfig(),
  };
}
```

---

## 4. Authentication & Token Refresh

**Priority:** High

**Current State:** No authentication error handling or token refresh support.

**Proposed Features:**
- Automatic 401 detection and token refresh flow
- Request queue during token refresh (prevent parallel refresh)
- Configurable refresh callback
- Automatic request replay after successful refresh
- Support for multiple auth schemes
- Dedicated `AuthenticationFailure` and `AuthorizationFailure` types

**Example API:**
```dart
SimpleNetworkHandler.setAuthConfig(AuthConfig(
  onUnauthorized: () async {
    final newToken = await authService.refreshToken();
    return newToken != null;
  },
  maxRefreshAttempts: 1,
));
```

---

## 5. Offline Detection & Request Queueing

**Priority:** Medium-High

**Current State:** Connection errors are mapped to failures but no proactive offline handling.

**Proposed Features:**
- Network connectivity monitoring
- Automatic request queueing when offline
- Configurable queue persistence (in-memory vs. persistent)
- Queue replay when connectivity restored
- Offline-first mode option
- Dedicated `OfflineFailure` with queued status

**Example API:**
```dart
SimpleNetworkHandler.setOfflineConfig(OfflineConfig(
  enableQueueing: true,
  maxQueueSize: 50,
  persistQueue: true,
  onConnectivityChanged: (isOnline) => print('Online: $isOnline'),
));
```

---

## 6. Circuit Breaker Pattern

**Priority:** Medium

**Current State:** No circuit breaker to prevent cascading failures.

**Proposed Features:**
- Per-endpoint circuit breakers
- Configurable failure threshold and recovery timeout
- Half-open state for gradual recovery
- Circuit state change callbacks
- Dedicated `CircuitOpenFailure` type
- Global and endpoint-specific configuration

**Example API:**
```dart
class MyErrorRegistry extends ErrorRegistry {
  @override
  Map<String, CircuitBreakerConfig> get circuitBreakerRegistry => {
    'paymentService': CircuitBreakerConfig(
      failureThreshold: 5,
      recoveryTimeout: Duration(minutes: 1),
    ),
  };
}
```

---

## 7. Rate Limiting Support

**Priority:** Medium

**Current State:** No special handling for rate limit responses.

**Proposed Features:**
- Automatic detection of 429 responses
- Parse `Retry-After` header (both delta-seconds and HTTP-date)
- Automatic request delay/retry based on Retry-After
- Client-side rate limiting (request throttling)
- Per-endpoint rate limit configuration
- Dedicated `RateLimitFailure` with retry timing

**Example API:**
```dart
class MyErrorRegistry extends ErrorRegistry {
  @override
  Map<String, RateLimitConfig> get rateLimitRegistry => {
    'searchApi': RateLimitConfig(
      autoRetry: true,
      maxWait: Duration(seconds: 60),
      clientSideLimit: RateLimit(100, Duration(minutes: 1)),
    ),
  };
}
```

---

## 8. Response Caching

**Priority:** Medium

**Current State:** No caching support.

**Proposed Features:**
- Cache successful responses with configurable TTL
- Cache key generation (URL, headers, body hash)
- Support for cache-control headers
- Stale-while-revalidate pattern
- Manual cache invalidation
- Memory and disk cache options
- Return cached data on error (fallback)

**Example API:**
```dart
final result = await SimpleNetworkHandler.safeCall(
  () => api.getProducts(),
  cache: CacheConfig(
    ttl: Duration(minutes: 5),
    staleWhileRevalidate: true,
    fallbackOnError: true,
  ),
);
```

---

## 9. Progress Tracking

**Priority:** Medium

**Current State:** No upload/download progress support.

**Proposed Features:**
- Progress callbacks for uploads and downloads
- Progress percentage and bytes transferred
- Estimated time remaining
- Integration with `safeCall()` options
- Support for chunked transfers

**Example API:**
```dart
final result = await SimpleNetworkHandler.safeCall(
  () => api.uploadFile(file),
  onSendProgress: (sent, total) => print('$sent / $total'),
  onReceiveProgress: (received, total) => print('$received / $total'),
);
```

---

## 10. Enhanced Logging & Observability

**Priority:** Medium

**Current State:** Basic debug logging with print statements.

**Proposed Features:**
- Structured logging with log levels (debug, info, warn, error)
- Custom logger integration (support for popular packages)
- Request/response logging with sensitive data redaction
- Correlation IDs for request tracing
- Metrics collection hooks (success rate, latency, error distribution)
- Integration points for APM tools

**Example API:**
```dart
SimpleNetworkHandler.setLogger(CustomLogger(
  level: LogLevel.info,
  redactHeaders: ['Authorization', 'Cookie'],
  onMetric: (metric) => analytics.track(metric),
));
```

---

## 11. Failure Categorization

**Priority:** Medium

**Current State:** All failures extend base `Failure` class but no categorization.

**Proposed Features:**
- Failure categories: Recoverable, NonRecoverable, Retryable, UserActionRequired
- `isRecoverable` and `suggestedAction` properties
- Retry hints in failure objects
- User-facing vs. developer-facing error separation
- Error codes for programmatic handling

**Example API:**
```dart
abstract class Failure {
  FailureCategory get category;
  bool get isRecoverable;
  SuggestedAction? get suggestedAction;
  String? get errorCode;
}

enum FailureCategory {
  network,      // Connectivity issues
  server,       // 5xx errors
  client,       // 4xx errors
  auth,         // Authentication/authorization
  validation,   // Request validation
  timeout,      // Timeout errors
  unknown,      // Unmapped errors
}
```

---

## 12. Testing Utilities

**Priority:** Medium

**Current State:** Example tests exist but no testing utilities for package consumers.

**Proposed Features:**
- Mock `SimpleNetworkHandler` for unit tests
- Predefined failure factories for testing
- Response simulation utilities
- Network condition simulation (latency, packet loss)
- Test mode flag to bypass real network calls

**Example API:**
```dart
// In test setup
SimpleNetworkHandler.setTestMode(
  responses: {
    'getUserById': Either.right(mockUser),
    'getProducts': Either.left(ServerFailure()),
  },
);
```

---

## 13. Localization Support

**Priority:** Low-Medium

**Current State:** `getTitle()` and `getSubtitle()` accept `BuildContext` but no i18n utilities.

**Proposed Features:**
- Built-in error message localization
- Language pack registration
- Fallback language support
- Interpolation for dynamic error messages
- Integration with popular i18n packages (intl, easy_localization)

**Example API:**
```dart
SimpleNetworkHandler.setLocalization(LocalizationConfig(
  defaultLocale: 'en',
  translations: {
    'en': EnglishErrorMessages(),
    'es': SpanishErrorMessages(),
  },
));
```

---

## 14. Request Transformation & Middleware

**Priority:** Low-Medium

**Current State:** Uses Dio interceptor for error mapping only.

**Proposed Features:**
- Pre-request transformation hooks
- Post-response transformation hooks
- Middleware chain for cross-cutting concerns
- Request/response modification capabilities
- Conditional middleware execution

**Example API:**
```dart
SimpleNetworkHandler.addMiddleware([
  LoggingMiddleware(),
  AuthHeaderMiddleware(),
  CacheMiddleware(),
  RetryMiddleware(),
]);
```

---

## 15. Batch Request Handling

**Priority:** Low

**Current State:** Single request handling only.

**Proposed Features:**
- Execute multiple requests in parallel
- Collect results as `List<Either<Failure, T>>`
- Configurable failure behavior (fail-fast vs. collect-all)
- Shared error handling for batch
- Progress tracking for batch operations

**Example API:**
```dart
final results = await SimpleNetworkHandler.batchCall([
  () => api.getUser(1),
  () => api.getUser(2),
  () => api.getUser(3),
], parallelism: 2);
```

---

## 16. Response Validation

**Priority:** Low

**Current State:** No response validation before parsing.

**Proposed Features:**
- Schema validation for responses
- Custom validators per endpoint
- Validation failure type with details
- Optional strict mode
- JSON Schema support

**Example API:**
```dart
final result = await SimpleNetworkHandler.safeCall(
  () => api.getData(),
  validator: ResponseValidator(
    requiredFields: ['id', 'name'],
    schema: userSchema,
  ),
);
```

---

## Implementation Priority Matrix

| Feature | Priority | Complexity | Impact |
|---------|----------|------------|--------|
| Retry Mechanism | High | Medium | High |
| Request Cancellation | High | Low | High |
| Timeout Configuration | High | Low | Medium |
| Auth & Token Refresh | High | High | High |
| Offline Detection & Queueing | Medium-High | High | High |
| Circuit Breaker | Medium | Medium | Medium |
| Rate Limiting | Medium | Medium | Medium |
| Response Caching | Medium | High | Medium |
| Progress Tracking | Medium | Low | Medium |
| Enhanced Logging | Medium | Medium | Medium |
| Failure Categorization | Medium | Low | Medium |
| Testing Utilities | Medium | Medium | High |
| Localization Support | Low-Medium | Medium | Low |
| Request Middleware | Low-Medium | Medium | Medium |
| Batch Requests | Low | Medium | Low |
| Response Validation | Low | Medium | Low |

---

## Recommended Implementation Order

### Phase 1: Core Reliability
1. Retry Mechanism
2. Request Cancellation
3. Timeout Configuration

### Phase 2: Production Essentials
4. Auth & Token Refresh
5. Enhanced Logging & Observability
6. Failure Categorization

### Phase 3: Resilience Patterns
7. Circuit Breaker
8. Rate Limiting Support
9. Offline Detection & Queueing

### Phase 4: Developer Experience
10. Testing Utilities
11. Response Caching
12. Progress Tracking

### Phase 5: Advanced Features
13. Localization Support
14. Request Middleware
15. Batch Requests
16. Response Validation

---

## Conclusion

The Simple Network Handler package has a solid foundation for error handling with its Either pattern and Dio integration. The features above would transform it into a comprehensive, production-ready network layer solution that handles the full spectrum of real-world networking challenges while remaining backend-agnostic and framework-independent.
