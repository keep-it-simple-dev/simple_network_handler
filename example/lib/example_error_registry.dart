import 'package:dio/dio.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:simple_network_handler_example/network/example_api.dart';
import 'package:simple_network_handler_example/models/example_failure.dart';

/// Example error registry for getUserById endpoint
class ExampleErrorRegistry extends ErrorRegistry {
  @override
  ErrorModelRegistry get endpointRegistry => {
        // Global error mappings
        '*': {
          500: (json) => Left(ServerFailure()),
        },
        
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
}