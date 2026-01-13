import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

// Test failure class
class TestFailure extends Failure {
  final String message;
  
  const TestFailure(this.message);
  
  @override
  String getTitle(context) => message;
  
  @override
  String getSubtitle(context) => '';
  
  @override
  String toString() => 'TestFailure($message)';
}

// Test success response
class TestUser {
  final int id;
  final String name;
  
  TestUser({required this.id, required this.name});
  
  factory TestUser.fromJson(Map<String, dynamic> json) {
    return TestUser(
      id: json['id'],
      name: json['name'],
    );
  }
}

// Error registry that maps responses to Either
class TestErrorRegistry extends ErrorRegistry {
  @override
  ErrorModelRegistry get endpointRegistry => {
    '/api/users': {
      400: (json) => Left(TestFailure('Bad Request: ${json['error']}')),
      404: (json) => const Left(TestFailure('User Not Found')),
      200: (json) => Right(TestUser.fromJson(json)),
    },
    '*': {
      500: (json) => const Left(TestFailure('Server Error')),
    },
  };

  @override
  Failure get genericError => const TestFailure('Generic Network Error');

  @override
  DioErrorRegistry get dioRegistry => {
    DioExceptionType.connectionTimeout: const TestFailure('Connection Timeout'),
  };

  @override
  GeneralErrorRegistry get generalRegistry => {};
}

// Error registry with retry configuration
class TestErrorRegistryWithRetry extends ErrorRegistry {
  int retryCallbackCount = 0;

  @override
  ErrorModelRegistry get endpointRegistry => {
    '*': {
      500: (json) => const Left(TestFailure('Server Error')),
    },
  };

  @override
  Failure get genericError => const TestFailure('Generic Network Error');

  @override
  DioErrorRegistry get dioRegistry => {
    DioExceptionType.connectionTimeout: const TestFailure('Connection Timeout'),
    DioExceptionType.connectionError: const TestFailure('Connection Error'),
  };

  @override
  GeneralErrorRegistry get generalRegistry => {};

  @override
  RetryConfig? get defaultRetryConfig => RetryConfig(
        maxAttempts: 3,
        initialDelay: const Duration(milliseconds: 10),
        backoffMultiplier: 1.0,
        useJitter: false,
      );

  @override
  void Function(int attempt, Duration delay, Object error)? get onRetry =>
      (attempt, delay, error) {
        retryCallbackCount++;
      };
}

// Error registry with endpoint-specific retry
class TestErrorRegistryWithEndpointRetry extends ErrorRegistry {
  @override
  ErrorModelRegistry get endpointRegistry => const {};

  @override
  Failure get genericError => const TestFailure('Generic Network Error');

  @override
  DioErrorRegistry get dioRegistry => {
    DioExceptionType.connectionTimeout: const TestFailure('Connection Timeout'),
  };

  @override
  GeneralErrorRegistry get generalRegistry => {};

  @override
  RetryRegistry get retryRegistry => {
    '/api/retryable': const RetryConfig(
      maxAttempts: 2,
      initialDelay: Duration(milliseconds: 10),
      useJitter: false,
    ),
    '/api/no-retry': RetryConfig.disabled,
  };
}

// Mock HTTP adapter that simulates real HTTP responses
class TestHttpAdapter implements HttpClientAdapter {
  final Map<String, MockHttpResponse> _responses = {};
  
  void mockResponse(String path, MockHttpResponse response) {
    _responses[path] = response;
  }
  
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final mockResponse = _responses[options.path];
    if (mockResponse == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'No mock response configured for ${options.path}',
      );
    }
    
    return ResponseBody.fromString(
      jsonEncode(mockResponse.data),
      mockResponse.statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }
  
  @override
  void close({bool force = false}) {
    _responses.clear();
  }
}

class MockHttpResponse {
  final int statusCode;
  final Map<String, dynamic> data;
  
  MockHttpResponse({required this.statusCode, required this.data});
}

void main() {
  group('Complete Flow Integration Tests', () {
    late Dio dio;
    late TestErrorRegistry errorRegistry;
    late TestHttpAdapter httpAdapter;
    
    setUp(() {
      // Setup components
      dio = Dio();
      errorRegistry = TestErrorRegistry();
      httpAdapter = TestHttpAdapter();
      
      // Configure Dio with our test adapter and interceptor
      dio.httpClientAdapter = httpAdapter;
      dio.interceptors.add(ErrorMappingInterceptor(errorRegistry: errorRegistry));
      
      // Setup NetworkHandler
      SimpleNetworkHandler.setErrorRegistry(errorRegistry);
    });
    
    tearDown(() {
      httpAdapter.close();
    });
    
    test('should handle successful 200 response through complete flow', () async {
      // Arrange - Mock a successful HTTP response
      httpAdapter.mockResponse('/api/users', MockHttpResponse(
        statusCode: 200,
        data: {'id': 123, 'name': 'John Doe'},
      ));
      
      // Act - Make request through complete flow: HTTP → Interceptor → NetworkHandler
      final result = await SimpleNetworkHandler.safeCall<TestUser>(
        () async {
          final response = await dio.get('/api/users');
          // This should not be reached because interceptor will process it
          return TestUser.fromJson(response.data);
        },
      );
      
      // Assert - Should get the success value from the error registry mapping
      expect(result.isRight(), true);
      result.fold(
        (failure) => fail('Should not be failure: $failure'),
        (success) {
          expect(success, isA<TestUser>());
          expect(success.id, equals(123));
          expect(success.name, equals('John Doe'));
        },
      );
    });
    
    test('should handle 400 error response through complete flow', () async {
      // Arrange - Mock a 400 error response
      httpAdapter.mockResponse('/api/users', MockHttpResponse(
        statusCode: 400,
        data: {'error': 'Invalid user data'},
      ));
      
      // Act - Make request through complete flow
      final result = await SimpleNetworkHandler.safeCall<TestUser>(
        () async {
          final response = await dio.post('/api/users');
          return TestUser.fromJson(response.data);
        },
      );
      
      // Assert - Should get the error from the error registry mapping
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<TestFailure>());
          expect((failure as TestFailure).message, equals('Bad Request: Invalid user data'));
        },
        (success) => fail('Should be failure'),
      );
    });
    
    test('should handle 404 error response through complete flow', () async {
      // Arrange - Mock a 404 error response
      httpAdapter.mockResponse('/api/users', MockHttpResponse(
        statusCode: 404,
        data: {'message': 'User not found'},
      ));
      
      // Act
      final result = await SimpleNetworkHandler.safeCall<TestUser>(
        () async {
          final response = await dio.get('/api/users');
          return TestUser.fromJson(response.data);
        },
      );
      
      // Assert - Should get the specific 404 error from registry
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<TestFailure>());
          expect((failure as TestFailure).message, equals('User Not Found'));
        },
        (success) => fail('Should be failure'),
      );
    });
    
    test('should handle global 500 error through complete flow', () async {
      // Arrange - Mock a 500 error for an endpoint not specifically mapped
      httpAdapter.mockResponse('/api/other', MockHttpResponse(
        statusCode: 500,
        data: {'error': 'Internal server error'},
      ));
      
      // Act
      final result = await SimpleNetworkHandler.safeCall<String>(
        () async {
          final response = await dio.get('/api/other');
          return response.data.toString();
        },
      );
      
      // Assert - Should get the global 500 error from registry
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<TestFailure>());
          expect((failure as TestFailure).message, equals('Server Error'));
        },
        (success) => fail('Should be failure'),
      );
    });
    
    test('should handle connection timeout without interceptor processing', () async {
      // Act - Simulate connection timeout (no HTTP response)
      final result = await SimpleNetworkHandler.safeCall<String>(
        () => throw DioException(
          requestOptions: RequestOptions(path: '/api/timeout'),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      
      // Assert - Should use Dio registry mapping
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<TestFailure>());
          expect((failure as TestFailure).message, equals('Connection Timeout'));
        },
        (success) => fail('Should be failure'),
      );
    });
    
    test('should handle unmapped status code through complete flow', () async {
      // Arrange - Mock a status code not mapped in registry
      httpAdapter.mockResponse('/api/users', MockHttpResponse(
        statusCode: 418, // I'm a teapot - not mapped
        data: {'message': 'I am a teapot'},
      ));

      // Act
      final result = await SimpleNetworkHandler.safeCall<TestUser>(
        () async {
          final response = await dio.get('/api/users');
          return TestUser.fromJson(response.data);
        },
      );

      // Assert - Should fall back to generic error since no mapping exists
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<TestFailure>());
          expect((failure as TestFailure).message, equals('Generic Network Error'));
        },
        (success) => fail('Should be failure'),
      );
    });
  });

  // ===== Phase 1: Retry Tests =====
  group('Retry Mechanism Tests', () {
    test('should retry on connection timeout and succeed', () async {
      // Arrange
      final errorRegistry = TestErrorRegistryWithRetry();
      SimpleNetworkHandler.setErrorRegistry(errorRegistry);

      int callCount = 0;

      // Act - Simulate failure then success
      final result = await SimpleNetworkHandler.safeCall<String>(
        () async {
          callCount++;
          if (callCount < 3) {
            throw DioException(
              requestOptions: RequestOptions(path: '/api/test'),
              type: DioExceptionType.connectionTimeout,
            );
          }
          return 'success';
        },
      );

      // Assert
      expect(result.isRight(), true);
      expect(callCount, equals(3)); // 1 initial + 2 retries
      expect(errorRegistry.retryCallbackCount, equals(2)); // 2 retry callbacks
    });

    test('should return failure after exhausting retries', () async {
      // Arrange
      final errorRegistry = TestErrorRegistryWithRetry();
      SimpleNetworkHandler.setErrorRegistry(errorRegistry);

      int callCount = 0;

      // Act - Always fail
      final result = await SimpleNetworkHandler.safeCall<String>(
        () async {
          callCount++;
          throw DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            type: DioExceptionType.connectionTimeout,
          );
        },
      );

      // Assert
      expect(result.isLeft(), true);
      expect(callCount, equals(4)); // 1 initial + 3 retries
      result.fold(
        (failure) {
          expect(failure, isA<TestFailure>());
          expect((failure as TestFailure).message, equals('Connection Timeout'));
        },
        (success) => fail('Should be failure'),
      );
    });

    test('should not retry on non-retryable status codes', () async {
      // Arrange
      final errorRegistry = TestErrorRegistryWithRetry();
      SimpleNetworkHandler.setErrorRegistry(errorRegistry);

      int callCount = 0;

      // Act - 404 is not in default retryStatusCodes
      final result = await SimpleNetworkHandler.safeCall<String>(
        () async {
          callCount++;
          throw DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            type: DioExceptionType.badResponse,
            response: Response(
              statusCode: 404,
              requestOptions: RequestOptions(path: '/api/test'),
            ),
          );
        },
      );

      // Assert - Should not retry
      expect(result.isLeft(), true);
      expect(callCount, equals(1)); // Only initial call
    });

    test('should retry on 500 status code', () async {
      // Arrange
      final errorRegistry = TestErrorRegistryWithRetry();
      SimpleNetworkHandler.setErrorRegistry(errorRegistry);

      int callCount = 0;

      // Act
      final result = await SimpleNetworkHandler.safeCall<String>(
        () async {
          callCount++;
          if (callCount < 2) {
            throw DioException(
              requestOptions: RequestOptions(path: '/api/test'),
              type: DioExceptionType.badResponse,
              response: Response(
                statusCode: 500,
                requestOptions: RequestOptions(path: '/api/test'),
              ),
            );
          }
          return 'success';
        },
      );

      // Assert
      expect(result.isRight(), true);
      expect(callCount, equals(2)); // 1 initial + 1 retry
    });

    test('should use per-call retry config to override registry', () async {
      // Arrange
      final errorRegistry = TestErrorRegistryWithRetry();
      SimpleNetworkHandler.setErrorRegistry(errorRegistry);

      int callCount = 0;

      // Act - Override with per-call config
      final result = await SimpleNetworkHandler.safeCall<String>(
        () async {
          callCount++;
          throw DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            type: DioExceptionType.connectionTimeout,
          );
        },
        options: CallOptions(
          retry: const RetryConfig(
            maxAttempts: 1,
            initialDelay: Duration(milliseconds: 5),
            useJitter: false,
          ),
        ),
      );

      // Assert - Should only retry once (per-call config)
      expect(result.isLeft(), true);
      expect(callCount, equals(2)); // 1 initial + 1 retry
    });

    test('should disable retry with CallOptions.noRetry()', () async {
      // Arrange
      final errorRegistry = TestErrorRegistryWithRetry();
      SimpleNetworkHandler.setErrorRegistry(errorRegistry);

      int callCount = 0;

      // Act - Disable retry
      final result = await SimpleNetworkHandler.safeCall<String>(
        () async {
          callCount++;
          throw DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            type: DioExceptionType.connectionTimeout,
          );
        },
        options: CallOptions.noRetry(),
      );

      // Assert - Should not retry
      expect(result.isLeft(), true);
      expect(callCount, equals(1)); // Only initial call
    });
  });

  // ===== Phase 1: Cancellation Tests =====
  group('Cancellation Tests', () {
    test('should return CancellationFailure when request is cancelled', () async {
      // Arrange
      final errorRegistry = TestErrorRegistry();
      SimpleNetworkHandler.setErrorRegistry(errorRegistry);

      // Act
      final result = await SimpleNetworkHandler.safeCall<String>(
        () async {
          throw DioException(
            requestOptions: RequestOptions(path: '/api/test'),
            type: DioExceptionType.cancel,
            message: 'User cancelled',
          );
        },
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<CancellationFailure>());
          expect((failure as CancellationFailure).reason, equals('User cancelled'));
        },
        (success) => fail('Should be failure'),
      );
    });

    test('should return CancellationFailure when cancelToken is pre-cancelled', () async {
      // Arrange
      final errorRegistry = TestErrorRegistry();
      SimpleNetworkHandler.setErrorRegistry(errorRegistry);

      final cancelToken = CancelToken();
      cancelToken.cancel('Pre-cancelled');

      int callCount = 0;

      // Act
      final result = await SimpleNetworkHandler.safeCall<String>(
        () async {
          callCount++;
          return 'success';
        },
        options: CallOptions(cancelToken: cancelToken),
      );

      // Assert
      expect(result.isLeft(), true);
      expect(callCount, equals(0)); // Request should not even be made
      result.fold(
        (failure) {
          expect(failure, isA<CancellationFailure>());
        },
        (success) => fail('Should be failure'),
      );
    });
  });

  // ===== Phase 1: RetryConfig Unit Tests =====
  group('RetryConfig Tests', () {
    test('should calculate exponential backoff correctly', () {
      final config = const RetryConfig(
        initialDelay: Duration(seconds: 1),
        backoffMultiplier: 2.0,
        useJitter: false,
      );

      expect(config.getDelayForAttempt(0), equals(const Duration(seconds: 1)));
      expect(config.getDelayForAttempt(1), equals(const Duration(seconds: 2)));
      expect(config.getDelayForAttempt(2), equals(const Duration(seconds: 4)));
    });

    test('should respect maxDelay cap', () {
      final config = const RetryConfig(
        initialDelay: Duration(seconds: 10),
        backoffMultiplier: 10.0,
        maxDelay: Duration(seconds: 30),
        useJitter: false,
      );

      // 10 * 10^2 = 1000, but capped at 30
      expect(config.getDelayForAttempt(2), equals(const Duration(seconds: 30)));
    });

    test('should identify disabled config', () {
      expect(RetryConfig.disabled.isDisabled, isTrue);
      expect(const RetryConfig(maxAttempts: 0).isDisabled, isTrue);
      expect(const RetryConfig(maxAttempts: 1).isDisabled, isFalse);
    });

    test('shouldRetry returns false when maxAttempts exceeded', () {
      final config = const RetryConfig(maxAttempts: 2);
      final error = DioException(
        type: DioExceptionType.connectionTimeout,
        requestOptions: RequestOptions(),
      );

      expect(config.shouldRetry(error, 0), isTrue);
      expect(config.shouldRetry(error, 1), isTrue);
      expect(config.shouldRetry(error, 2), isFalse);
    });

    test('shouldRetry respects custom retryWhen predicate', () {
      final config = RetryConfig(
        maxAttempts: 3,
        retryWhen: (error, attempt) => attempt == 0, // Only retry on first attempt
      );
      final error = DioException(
        type: DioExceptionType.connectionTimeout,
        requestOptions: RequestOptions(),
      );

      expect(config.shouldRetry(error, 0), isTrue);
      expect(config.shouldRetry(error, 1), isFalse);
    });
  });

  // ===== Phase 1: TimeoutConfig Unit Tests =====
  group('TimeoutConfig Tests', () {
    test('should merge configs correctly', () {
      const base = TimeoutConfig(
        connectTimeout: Duration(seconds: 5),
        sendTimeout: Duration(seconds: 10),
        receiveTimeout: Duration(seconds: 15),
      );
      const override = TimeoutConfig(
        connectTimeout: Duration(seconds: 20),
        // sendTimeout not set - should keep base value
        receiveTimeout: Duration(seconds: 30),
      );

      final merged = base.mergeWith(override);

      expect(merged.connectTimeout, equals(const Duration(seconds: 20)));
      expect(merged.sendTimeout, equals(const Duration(seconds: 10))); // Kept from base
      expect(merged.receiveTimeout, equals(const Duration(seconds: 30)));
    });

    test('TimeoutConfig.all creates uniform timeouts', () {
      final config = TimeoutConfig.all(const Duration(seconds: 10));

      expect(config.connectTimeout, equals(const Duration(seconds: 10)));
      expect(config.sendTimeout, equals(const Duration(seconds: 10)));
      expect(config.receiveTimeout, equals(const Duration(seconds: 10)));
    });

    test('presets have expected values', () {
      expect(TimeoutConfig.quick.connectTimeout, equals(const Duration(seconds: 5)));
      expect(TimeoutConfig.standard.connectTimeout, equals(const Duration(seconds: 10)));
      expect(TimeoutConfig.longRunning.connectTimeout, equals(const Duration(seconds: 15)));
    });
  });

  // ===== Phase 1: CallOptions Tests =====
  group('CallOptions Tests', () {
    test('noRetry factory creates disabled retry config', () {
      final options = CallOptions.noRetry();

      expect(options.retry, equals(RetryConfig.disabled));
      expect(options.retry!.isDisabled, isTrue);
    });

    test('withRetry factory sets retry config', () {
      const retryConfig = RetryConfig(maxAttempts: 5);
      final options = CallOptions.withRetry(retryConfig);

      expect(options.retry, equals(retryConfig));
    });

    test('withTimeout factory sets timeout config', () {
      const timeoutConfig = TimeoutConfig.quick;
      final options = CallOptions.withTimeout(timeoutConfig);

      expect(options.timeout, equals(timeoutConfig));
    });

    test('cancellable factory sets cancel token', () {
      final cancelToken = CancelToken();
      final options = CallOptions.cancellable(cancelToken);

      expect(options.cancelToken, equals(cancelToken));
    });
  });
}