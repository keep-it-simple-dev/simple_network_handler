import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_network_handler/network_handler.dart';

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
      NetworkHandler.setErrorRegistry(errorRegistry);
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
      final result = await NetworkHandler.safeNetworkCall<TestUser>(
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
      final result = await NetworkHandler.safeNetworkCall<TestUser>(
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
      final result = await NetworkHandler.safeNetworkCall<TestUser>(
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
      final result = await NetworkHandler.safeNetworkCall<String>(
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
      final result = await NetworkHandler.safeNetworkCall<String>(
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
      final result = await NetworkHandler.safeNetworkCall<TestUser>(
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
}