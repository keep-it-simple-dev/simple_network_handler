import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

class SimpleNetworkHandler {
  static ErrorRegistry? _errorRegistry;
  static bool _enableDebugLogging = false;

  static void setErrorRegistry(ErrorRegistry registry) {
    _errorRegistry = registry;
  }

  static void setDebugLogging(bool enabled) {
    _enableDebugLogging = enabled;
  }

  static void _logError(Object error, StackTrace stackTrace) {
    if (_enableDebugLogging) {
      debugPrint('SimpleNetworkHandler Error: $error');
      debugPrint('Stack trace:\n$stackTrace');
    }
  }

  static Future<Either<Failure, T>> safeCall<T>(
    Future<T> Function() request, {
    Either<Failure, T>? Function(DioException)? onEndpointError,
  }) async {
    assert(_errorRegistry != null,
        'Error registry must be set before calling safeNetworkCall');
    try {
      final result = await request();
      return Right(result);
    } on DioException catch (e, stackTrace) {
      _logError(e, stackTrace);

      // General error handling
      final dynamic parsedEither =
          e.response?.extra[_errorRegistry!.parsedEitherKey];
      if (parsedEither is Either<Failure, dynamic>) {
        return parsedEither.fold(
          (failure) => Left<Failure, T>(failure),
          (success) => Right<Failure, T>(success as T),
        );
      }

      // Endpoint-specific error handling
      if (onEndpointError != null) {
        final endpointFailure = onEndpointError(e);
        if (endpointFailure != null) {
          return endpointFailure;
        }
      }

      // Handle specific network error types using registry
      if (_errorRegistry != null) {
        final dioFailure = _errorRegistry!.dioRegistry[e.type];
        if (dioFailure != null) {
          return Left(dioFailure);
        }
      }

      // Fallback to generic error
      return Left(_errorRegistry!.genericError);
    } catch (e, stackTrace) {
      _logError(e, stackTrace);

      // Handle custom exceptions using general error registry
      if (_errorRegistry != null) {
        final failureFactory = _errorRegistry!.generalRegistry[e.runtimeType];
        if (failureFactory != null) {
          return Left(failureFactory(e));
        }
      }

      // Fallback to generic error for unhandled exceptions
      return Left(_errorRegistry!.genericError);
    }
  }
}
