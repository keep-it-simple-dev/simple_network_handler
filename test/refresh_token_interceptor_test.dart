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

// Error registry used for the composition tests
class TestErrorRegistry extends ErrorRegistry {
  @override
  ErrorModelRegistry get endpointRegistry => {
    '/api/users': {
      401: (json) => const Left(TestFailure('Unauthorized')),
    },
  };

  @override
  Failure get genericError => const TestFailure('Generic Network Error');

  @override
  DioErrorRegistry get dioRegistry => {};

  @override
  GeneralErrorRegistry get generalRegistry => {};
}

// In-memory token store
class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore({this.token});

  String? token;
  int writeCount = 0;

  @override
  Future<String?> readAccessToken() async => token;

  @override
  Future<void> writeAccessToken(String newToken) async {
    token = newToken;
    writeCount++;
  }
}

class RecordedRequest {
  final String path;
  final String? authorization;

  RecordedRequest(this.path, this.authorization);
}

// Mock HTTP adapter that authorizes requests based on the bearer token:
// requests carrying `Bearer <validToken>` succeed, everything else gets a 401.
class TokenAwareHttpAdapter implements HttpClientAdapter {
  TokenAwareHttpAdapter({this.validToken = 'new-token'});

  final String validToken;
  final List<RecordedRequest> requests = [];
  static const String refreshPath = '/auth/refresh';
  int refreshCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authorization = options.headers['Authorization'] as String?;
    requests.add(RecordedRequest(options.path, authorization));

    if (options.path == refreshPath) {
      refreshCalls++;
      return _jsonResponse(200, {'access_token': validToken});
    }
    if (authorization == 'Bearer $validToken') {
      return _jsonResponse(200, {'id': 123, 'name': 'John Doe'});
    }
    return _jsonResponse(401, {'error': 'Token expired'});
  }

  ResponseBody _jsonResponse(int statusCode, Map<String, dynamic> data) {
    return ResponseBody.fromString(
      jsonEncode(data),
      statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {
    requests.clear();
  }
}

void main() {
  group('RefreshTokenInterceptor', () {
    late Dio dio;
    late Dio bareDio;
    late TokenAwareHttpAdapter httpAdapter;
    late InMemoryTokenStore tokenStore;

    setUp(() {
      httpAdapter = TokenAwareHttpAdapter();
      tokenStore = InMemoryTokenStore(token: 'expired-token');

      // Bare Dio (no interceptors) used for refresh and replay, sharing the
      // mocked transport with the main instance.
      bareDio = Dio();
      bareDio.httpClientAdapter = httpAdapter;

      dio = Dio();
      dio.httpClientAdapter = httpAdapter;
    });

    tearDown(() {
      httpAdapter.close();
    });

    test('should refresh token and replay original request on 401', () async {
      // Arrange
      var refreshCalls = 0;
      dio.interceptors.add(RefreshTokenInterceptor(
        tokenStore: tokenStore,
        refreshToken: () async {
          refreshCalls++;
          return 'new-token';
        },
        httpClient: bareDio,
      ));

      // Act
      final response = await dio.get('/api/users');

      // Assert - Refresh ran once, the new token was persisted and the
      // request was replayed with the new header.
      expect(response.statusCode, equals(200));
      expect(response.data['name'], equals('John Doe'));
      expect(refreshCalls, equals(1));
      expect(tokenStore.token, equals('new-token'));
      expect(
        httpAdapter.requests.map((request) => request.authorization).toList(),
        equals(['Bearer expired-token', 'Bearer new-token']),
      );
    });

    test('should run a single refresh for concurrent 401s (single-flight)',
        () async {
      // Arrange - Refresh is slow so all requests fail with the old token
      // before the new one is available.
      var refreshCalls = 0;
      dio.interceptors.add(RefreshTokenInterceptor(
        tokenStore: tokenStore,
        refreshToken: () async {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return 'new-token';
        },
        httpClient: bareDio,
      ));

      // Act - Fire concurrent requests that all 401 with the expired token
      final responses = await Future.wait([
        dio.get('/api/users'),
        dio.get('/api/users'),
        dio.get('/api/users'),
      ]);

      // Assert - All requests succeed after exactly one refresh
      expect(refreshCalls, equals(1));
      expect(tokenStore.writeCount, equals(1));
      for (final response in responses) {
        expect(response.statusCode, equals(200));
      }
      final replays = httpAdapter.requests
          .where((request) => request.authorization == 'Bearer new-token');
      expect(replays.length, equals(3));
    });

    test('should call onRefreshFailed and propagate the original error '
        'when refresh throws', () async {
      // Arrange
      Object? capturedError;
      var refreshFailedCalls = 0;
      dio.interceptors.add(RefreshTokenInterceptor(
        tokenStore: tokenStore,
        refreshToken: () async => throw StateError('refresh token revoked'),
        onRefreshFailed: (error) {
          refreshFailedCalls++;
          capturedError = error;
        },
        httpClient: bareDio,
      ));

      // Act & Assert - The original 401 is propagated
      try {
        await dio.get('/api/users');
        fail('Should have thrown a DioException');
      } on DioException catch (e) {
        expect(e.response?.statusCode, equals(401));
        expect(e.response?.data['error'], equals('Token expired'));
      }
      expect(refreshFailedCalls, equals(1));
      expect(capturedError, isA<StateError>());
      expect(tokenStore.token, equals('expired-token'));
    });

    test('should call onRefreshFailed when refresh returns null', () async {
      // Arrange
      var refreshFailedCalls = 0;
      dio.interceptors.add(RefreshTokenInterceptor(
        tokenStore: tokenStore,
        refreshToken: () async => null,
        onRefreshFailed: (_) => refreshFailedCalls++,
        httpClient: bareDio,
      ));

      // Act & Assert
      try {
        await dio.get('/api/users');
        fail('Should have thrown a DioException');
      } on DioException catch (e) {
        expect(e.response?.statusCode, equals(401));
      }
      expect(refreshFailedCalls, equals(1));
    });

    test('should not apply token or refresh for excluded paths', () async {
      // Arrange
      var refreshCalls = 0;
      dio.interceptors.add(RefreshTokenInterceptor(
        tokenStore: tokenStore,
        refreshToken: () async {
          refreshCalls++;
          return 'new-token';
        },
        excludedPaths: ['/api/public'],
        httpClient: bareDio,
      ));

      // Act & Assert - The 401 passes through untouched
      try {
        await dio.get('/api/public');
        fail('Should have thrown a DioException');
      } on DioException catch (e) {
        expect(e.response?.statusCode, equals(401));
      }
      expect(refreshCalls, equals(0));
      expect(httpAdapter.requests.single.authorization, isNull);
    });

    test('should execute RefreshRequest spec on the bare http client',
        () async {
      // Arrange - Declarative refresh request instead of a callback
      dio.interceptors.add(RefreshTokenInterceptor(
        tokenStore: tokenStore,
        refreshRequest: RefreshRequest(
          path: TokenAwareHttpAdapter.refreshPath,
          buildData: () => {'refresh_token': 'stored-refresh-token'},
          extractAccessToken: (response) =>
              (response.data as Map<String, dynamic>)['access_token']
                  as String?,
        ),
        httpClient: bareDio,
      ));

      // Act
      final response = await dio.get('/api/users');

      // Assert - The refresh endpoint was hit once, without the auth header
      expect(response.statusCode, equals(200));
      expect(httpAdapter.refreshCalls, equals(1));
      expect(tokenStore.token, equals('new-token'));
      final refreshRequest = httpAdapter.requests
          .singleWhere((r) => r.path == TokenAwareHttpAdapter.refreshPath);
      expect(refreshRequest.authorization, isNull);
    });

    group('composition with ErrorMappingInterceptor', () {
      setUp(() {
        SimpleNetworkHandler.setErrorRegistry(TestErrorRegistry());
      });

      test('should map the 401 to a Failure when refresh fails', () async {
        // Arrange - Refresh interceptor added BEFORE error mapping
        dio.interceptors.addAll([
          RefreshTokenInterceptor(
            tokenStore: tokenStore,
            refreshToken: () async => null,
            httpClient: bareDio,
          ),
          ErrorMappingInterceptor(errorRegistry: TestErrorRegistry()),
        ]);

        // Act
        final result = await SimpleNetworkHandler.safeCall<dynamic>(
          () => dio.get('/api/users'),
        );

        // Assert - The propagated 401 was mapped by the registry
        expect(result.isLeft(), true);
        result.fold(
          (failure) {
            expect(failure, isA<TestFailure>());
            expect((failure as TestFailure).message, equals('Unauthorized'));
          },
          (success) => fail('Should be failure'),
        );
      });

      test('should return success when refresh recovers the 401', () async {
        // Arrange
        dio.interceptors.addAll([
          RefreshTokenInterceptor(
            tokenStore: tokenStore,
            refreshToken: () async => 'new-token',
            httpClient: bareDio,
          ),
          ErrorMappingInterceptor(errorRegistry: TestErrorRegistry()),
        ]);

        // Act
        final result = await SimpleNetworkHandler.safeCall<String>(
          () async {
            final response = await dio.get('/api/users');
            return response.data['name'] as String;
          },
        );

        // Assert
        expect(result.isRight(), true);
        result.fold(
          (failure) => fail('Should not be failure: $failure'),
          (name) => expect(name, equals('John Doe')),
        );
      });
    });
  });
}
