import 'package:injectable/injectable.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:simple_network_handler_example/network/example_api.dart';
import 'package:simple_network_handler_example/models/example_models.dart';

/// Simple repository with one method
abstract class ExampleRepository {
  Future<Either<Failure, UserResponse>> getUserById(int id);
}

/// Repository implementation using SimpleNetworkHandler
@Singleton(as: ExampleRepository)
class ExampleRepositoryImpl implements ExampleRepository {
  final ExampleApi _apiClient;

  ExampleRepositoryImpl(this._apiClient);

  @override
  Future<Either<Failure, UserResponse>> getUserById(int id) async {
    return SimpleNetworkHandler.safeCall(
      () => _apiClient.getUserById(id),
    );
  }
}