import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:simple_network_handler_example/example_error_registry.dart';

/// In-memory token store for the example. In a real app back this with
/// secure storage (e.g. flutter_secure_storage).
@singleton
class ExampleTokenStore implements TokenStore {
  String? _accessToken;
  String? refreshToken;

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<void> writeAccessToken(String token) async => _accessToken = token;
}

/// Provides the Dio instance used by the API clients.
@module
abstract class ExampleNetworkModule {
  @Named('mainHttpClient')
  @singleton
  Dio mainHttpClient(ExampleTokenStore tokenStore) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

    // Order matters: the refresh interceptor must run BEFORE the error
    // mapping interceptor, so an expired session is refreshed (and the
    // request replayed) before the 401 is turned into a Failure.
    dio.interceptors.addAll([
      RefreshTokenInterceptor(
        tokenStore: tokenStore,
        // Executed on a separate bare Dio instance (no interceptors), so it
        // can never deadlock the queue or loop on its own 401s.
        refreshRequest: RefreshRequest(
          path: 'https://api.example.com/api/auth/refresh',
          buildData: () => {'refreshToken': tokenStore.refreshToken},
          extractAccessToken: (response) =>
              (response.data as Map<String, dynamic>)['accessToken']
                  as String?,
        ),
        excludedPaths: ['/api/auth/login'],
        onRefreshFailed: (error) {
          // The session can no longer be refreshed: force a logout here.
        },
      ),
      ErrorMappingInterceptor(errorRegistry: ExampleErrorRegistry()),
    ]);

    return dio;
  }
}
