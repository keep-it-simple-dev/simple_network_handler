import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:retrofit/retrofit.dart';
import 'package:simple_network_handler_example/models/example_models.dart';

part 'example_api.g.dart';

class ExampleApiPath {
  static const String getUserById = '/api/users/{id}';
}

@RestApi()
@singleton
abstract class ExampleApi {
  @factoryMethod
  factory ExampleApi(@Named('mainHttpClient') Dio dio) = _ExampleApi;

  /// Get user by ID
  @GET(ExampleApiPath.getUserById)
  Future<UserResponse> getUserById(@Path('id') int id);
}