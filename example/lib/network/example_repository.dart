import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:simple_network_handler_example/network/example_api.dart';
import 'package:simple_network_handler_example/models/example_models.dart';

/// Simple repository with one method
abstract class ExampleRepository {
  /// Get user by ID with optional cancellation support
  Future<Either<Failure, UserResponse>> getUserById(
    int id, {
    CancelToken? cancelToken,
  });

  /// Example: Get user with custom retry configuration
  Future<Either<Failure, UserResponse>> getUserByIdNoRetry(int id);

  /// Cancel any ongoing request
  void cancelCurrentRequest([String? reason]);

  /// Dispose resources
  void dispose();
}

/// Repository implementation using SimpleNetworkHandler
/// Demonstrates Phase 1 features: retry, cancellation, timeout
@Singleton(as: ExampleRepository)
class ExampleRepositoryImpl implements ExampleRepository {
  final ExampleApi _apiClient;

  /// Track current cancel token for request management
  CancelToken? _currentCancelToken;

  ExampleRepositoryImpl(this._apiClient);

  @override
  Future<Either<Failure, UserResponse>> getUserById(
    int id, {
    CancelToken? cancelToken,
  }) async {
    // Cancel any previous request
    _currentCancelToken?.cancel('New request started');
    _currentCancelToken = cancelToken ?? CancelToken();

    return SimpleNetworkHandler.safeCall(
      () => _apiClient.getUserById(id),
      // Pass endpoint path to enable endpoint-specific retry/timeout from registry
      endpointPath: ExampleApiPath.getUserById,
      // Pass cancel token for cancellation support
      options: CallOptions(cancelToken: _currentCancelToken),
    );
  }

  @override
  Future<Either<Failure, UserResponse>> getUserByIdNoRetry(int id) async {
    return SimpleNetworkHandler.safeCall(
      () => _apiClient.getUserById(id),
      endpointPath: ExampleApiPath.getUserById,
      // Disable retry for this specific call (overrides registry default)
      options: CallOptions.noRetry(),
    );
  }

  @override
  void cancelCurrentRequest([String? reason]) {
    _currentCancelToken?.cancel(reason ?? 'Request cancelled by user');
    _currentCancelToken = null;
  }

  @override
  void dispose() {
    cancelCurrentRequest('Repository disposed');
  }
}