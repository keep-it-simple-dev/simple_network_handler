import 'package:dio/dio.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

class ErrorMappingInterceptor extends Interceptor {
  final ErrorRegistry errorRegistry;

  ErrorMappingInterceptor({
    required this.errorRegistry,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Apply timeout configuration from registry
    final path = options.path;
    final timeoutConfig = errorRegistry.getTimeoutConfigForEndpoint(path);

    if (timeoutConfig != null) {
      if (timeoutConfig.connectTimeout != null) {
        options.connectTimeout = timeoutConfig.connectTimeout;
      }
      if (timeoutConfig.sendTimeout != null) {
        options.sendTimeout = timeoutConfig.sendTimeout;
      }
      if (timeoutConfig.receiveTimeout != null) {
        options.receiveTimeout = timeoutConfig.receiveTimeout;
      }
    }

    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final path = response.requestOptions.path;
    final status = response.statusCode;
    final data = response.data;
    if (status != null && data is Map<String, dynamic>) {
      // Try endpoint-specific first
      final endpointMap = errorRegistry.endpointRegistry[path];
      final eitherFactory = endpointMap?[status]
          // Fallback to global
          ??
          errorRegistry.endpointRegistry[errorRegistry.allEndpointsKey]?[status];
      if (eitherFactory != null) {
        try {
          final either = eitherFactory(data);
          // Attach the failure to the error for later use in response.extra
          DioException exception = DioException(
            requestOptions: response.requestOptions,
            type: DioExceptionType.unknown,
            response: response,
          );
          exception.response?.extra[errorRegistry.parsedEitherKey] = either;
          handler.reject(exception);
          return;
        } catch (_) {
          // fallback: do nothing, let Dio handle as usual
        }
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final path = err.requestOptions.path;
    final status = err.response?.statusCode;
    final data = err.response?.data;

    if (status != null && data is Map<String, dynamic>) {
      // Try endpoint-specific first
      final endpointMap = errorRegistry.endpointRegistry[path];
      final eitherFactory = endpointMap?[status]
          // Fallback to global
          ??
          errorRegistry.endpointRegistry[errorRegistry.allEndpointsKey]?[status];
      if (eitherFactory != null) {
        try {
          final either = eitherFactory(data);
          // Attach the failure to the error for later use in response.extra
          err.response?.extra[errorRegistry.parsedEitherKey] = either;
        } catch (_) {
          // fallback: do nothing, let Dio handle as usual
        }
      }
    }
    super.onError(err, handler);
  }
}
