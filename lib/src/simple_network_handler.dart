import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:simple_network_handler/simple_network_handler.dart';


class SimpleNetworkHandler {
  static ErrorRegistry? _errorRegistry;

  static void setErrorRegistry(ErrorRegistry registry) {
    _errorRegistry = registry;
  }

  static Future<Either<Failure, T>> safeCall<T>(
    Future<T> Function() request, {
    Either<Failure, T>? Function(DioException)? onEndpointError,
  }) async {
    assert(_errorRegistry != null, 'Error registry must be set before calling safeNetworkCall');
    try {
      final result = await request();
      return Right(result);
    } on DioException catch (e) {
      // General error handling
      final dynamic parsedEither = e.response?.extra[_errorRegistry!.parsedEitherKey];
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
    } catch (_) {
      rethrow;
    }
  }
}
