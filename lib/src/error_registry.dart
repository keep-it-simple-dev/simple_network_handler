import 'package:dio/dio.dart';
import 'package:simple_network_handler/simple_network_handler.dart';


typedef EitherFactory = Either<Failure, dynamic> Function(Map<String, dynamic> json);
typedef ErrorModelRegistry = Map<String, Map<int, EitherFactory>>;
typedef DioErrorRegistry = Map<DioExceptionType, Failure>;

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
}
