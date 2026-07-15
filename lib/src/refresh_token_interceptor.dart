import 'dart:async';

import 'package:dio/dio.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

/// Signature for a user-supplied refresh callback.
///
/// Returns the new access token, or `null` when the session could not be
/// refreshed (which triggers `onRefreshFailed`).
typedef RefreshTokenCallback = Future<String?> Function();

/// Signature for applying an access token to an outgoing request.
typedef HeaderApplier = void Function(
    RequestOptions options, String accessToken);

/// Signature for the callback invoked when a token refresh fails.
///
/// [error] is the exception thrown by the refresh call, or `null` when the
/// refresh completed but returned no token.
typedef RefreshFailedCallback = FutureOr<void> Function(Object? error);

/// Declarative description of the HTTP request that refreshes the session.
///
/// The request is executed on a separate bare [Dio] instance (no
/// interceptors). Reusing the instance the interceptor is attached to would
/// deadlock its queue (see dio issue #1612), and letting interceptors see the
/// refresh call can cause infinite 401 loops.
class RefreshRequest {
  const RefreshRequest({
    required this.path,
    this.method = 'POST',
    this.buildData,
    this.buildHeaders,
    required this.extractAccessToken,
  });

  /// The refresh endpoint. Use an absolute URL
  /// (e.g. `https://api.example.com/auth/refresh`) unless a custom
  /// `httpClient` with a `baseUrl` is passed to the interceptor.
  final String path;

  /// The HTTP method of the refresh request.
  final String method;

  /// Builds the request body, e.g. reads the refresh token from storage.
  final FutureOr<Object?> Function()? buildData;

  /// Builds the request headers, e.g. a `Cookie` or basic auth header.
  final FutureOr<Map<String, dynamic>?> Function()? buildHeaders;

  /// Extracts the new access token from the refresh response, or returns
  /// `null` when the response contains none.
  final String? Function(Response<dynamic> response) extractAccessToken;
}

/// Interceptor that transparently refreshes an expired access token and
/// replays the failed request.
///
/// Built on [QueuedInterceptorsWrapper]: while one refresh is running,
/// concurrent requests that fail with the same status are queued. Once the
/// refresh completes, queued requests detect that the stored token already
/// changed and are replayed with the new token without triggering another
/// refresh (single-flight).
///
/// On every request the current token is read from [tokenStore] and applied
/// through [applyHeader] (defaults to `Authorization: Bearer <token>`).
/// When a response status matches [triggerStatusCodes] (defaults to `[401]`)
/// and the path is not excluded, the interceptor:
///
/// 1. runs a single refresh via [refreshToken] or [refreshRequest],
/// 2. persists the new token to [tokenStore],
/// 3. replays the original request with the new header and resolves the
///    handler with the replay response.
///
/// If the refresh fails or returns `null`, [onRefreshFailed] is invoked
/// (force-logout hook) and the original error is propagated.
///
/// **Interceptor order matters**: add this interceptor *before*
/// [ErrorMappingInterceptor] so the refresh runs before error mapping turns
/// the 401 into a [Failure]:
///
/// ```dart
/// dio.interceptors.addAll([
///   RefreshTokenInterceptor(tokenStore: tokenStore, refreshToken: refresh),
///   ErrorMappingInterceptor(errorRegistry: MyErrorRegistry()),
/// ]);
/// ```
class RefreshTokenInterceptor extends QueuedInterceptorsWrapper {
  RefreshTokenInterceptor({
    required this.tokenStore,
    this.refreshToken,
    this.refreshRequest,
    this.triggerStatusCodes = const [401],
    this.excludedPaths = const [],
    HeaderApplier? applyHeader,
    this.onRefreshFailed,
    Dio? httpClient,
  })  : assert(
          (refreshToken == null) != (refreshRequest == null),
          'Provide exactly one of refreshToken or refreshRequest',
        ),
        applyHeader = applyHeader ?? _defaultHeaderApplier,
        _httpClient = httpClient ?? Dio();

  /// Key under which the token used by a request is stored in
  /// [RequestOptions.extra]. Used to detect that another request already
  /// refreshed the token while this one was in flight.
  static const String usedTokenKey = 'refreshTokenInterceptorUsedToken';

  /// Storage the access token is read from and persisted to.
  final TokenStore tokenStore;

  /// Callback that performs the refresh and returns the new access token.
  ///
  /// Provide either this or [refreshRequest]. If the callback performs an
  /// HTTP call, execute it on a bare [Dio] instance without interceptors.
  final RefreshTokenCallback? refreshToken;

  /// Declarative refresh request, executed on a separate bare [Dio] instance.
  ///
  /// Provide either this or [refreshToken]. Its [RefreshRequest.path] is
  /// automatically treated as an excluded path.
  final RefreshRequest? refreshRequest;

  /// Response status codes that trigger a token refresh.
  final List<int> triggerStatusCodes;

  /// Paths that never trigger a refresh and never get the token header
  /// applied, e.g. the refresh endpoint itself and public endpoints.
  final List<String> excludedPaths;

  /// Applies the access token to an outgoing request. Defaults to setting
  /// the `Authorization: Bearer <token>` header.
  final HeaderApplier applyHeader;

  /// Invoked when the refresh fails or returns no token, e.g. to force a
  /// logout. The original error is propagated afterwards.
  final RefreshFailedCallback? onRefreshFailed;

  /// Bare [Dio] instance (no interceptors) used to execute [refreshRequest]
  /// and to replay failed requests.
  final Dio _httpClient;

  static void _defaultHeaderApplier(
      RequestOptions options, String accessToken) {
    options.headers['Authorization'] = 'Bearer $accessToken';
  }

  bool _isExcluded(String path) =>
      path == refreshRequest?.path || excludedPaths.contains(path);

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isExcluded(options.path)) {
      final token = await _readToken();
      if (token != null) {
        applyHeader(options, token);
        options.extra[usedTokenKey] = token;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    if (statusCode == null ||
        !triggerStatusCodes.contains(statusCode) ||
        _isExcluded(err.requestOptions.path)) {
      handler.next(err);
      return;
    }

    final usedToken = err.requestOptions.extra[usedTokenKey];
    final currentToken = await _readToken();

    String? newToken;
    if (currentToken != null && currentToken != usedToken) {
      // The token was already refreshed by a request that failed earlier in
      // the queue (single-flight), only the replay is needed.
      newToken = currentToken;
    } else {
      Object? refreshError;
      try {
        newToken = await _refresh();
      } catch (error) {
        refreshError = error;
      }
      if (newToken == null) {
        try {
          await onRefreshFailed?.call(refreshError);
        } catch (_) {
          // Never let a failing callback break error propagation.
        }
        handler.next(err);
        return;
      }
      try {
        await tokenStore.writeAccessToken(newToken);
      } catch (_) {
        // A failing store must not prevent the replay of this request.
      }
    }

    try {
      handler.resolve(await _replay(err.requestOptions, newToken));
    } on DioException catch (replayError) {
      handler.next(replayError);
    } catch (_) {
      handler.next(err);
    }
  }

  Future<String?> _readToken() async {
    try {
      return await tokenStore.readAccessToken();
    } catch (_) {
      // Treat a failing store as having no token.
      return null;
    }
  }

  Future<String?> _refresh() async {
    if (refreshToken != null) {
      return refreshToken!();
    }
    final request = refreshRequest!;
    final response = await _httpClient.fetch<dynamic>(
      RequestOptions(
        path: request.path,
        baseUrl: _httpClient.options.baseUrl,
        method: request.method,
        data: await request.buildData?.call(),
        headers: await request.buildHeaders?.call(),
      ),
    );
    return request.extractAccessToken(response);
  }

  Future<Response<dynamic>> _replay(
      RequestOptions requestOptions, String accessToken) {
    applyHeader(requestOptions, accessToken);
    requestOptions.extra[usedTokenKey] = accessToken;
    return _httpClient.fetch<dynamic>(requestOptions);
  }
}
