import 'package:flutter/foundation.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../simple_network_handler_supabase.dart';

/// A handler for safely executing Supabase operations with centralized error handling.
///
/// This follows the same pattern as [SimpleNetworkHandler] but is designed
/// specifically for Supabase exceptions (AuthException, PostgrestException,
/// StorageException, FunctionException, etc.).
///
/// Usage:
/// ```dart
/// // Initialize once at app startup
/// SupabaseNetworkHandler.setErrorRegistry(MySupabaseErrorRegistry());
///
/// // Use in repositories
/// Future<Either<Failure, User>> getCurrentUser() {
///   return SupabaseNetworkHandler.safeCall(
///     () => supabase.auth.getUser(),
///   );
/// }
/// ```
class SupabaseNetworkHandler {
  static SupabaseErrorRegistry? _errorRegistry;
  static bool _enableDebugLogging = false;

  /// Sets the error registry for Supabase error handling.
  ///
  /// Must be called before any [safeCall] invocations, typically at app startup.
  static void setErrorRegistry(SupabaseErrorRegistry registry) {
    _errorRegistry = registry;
  }

  /// Enables or disables debug logging for Supabase errors.
  static void setDebugLogging(bool enabled) {
    _enableDebugLogging = enabled;
  }

  static void _logError(Object error, StackTrace stackTrace) {
    if (_enableDebugLogging) {
      debugPrint('SupabaseNetworkHandler Error: $error');
      debugPrint('Stack trace:\n$stackTrace');
    }
  }

  /// Safely executes a Supabase operation and returns an [Either] result.
  ///
  /// - On success: Returns `Right(result)`
  /// - On failure: Returns `Left(Failure)` based on the error registry mappings
  ///
  /// The error handling priority is:
  /// 1. [onError] callback (if provided) for custom handling
  /// 2. Error registry mappings (auth, postgrest, storage, function, general)
  /// 3. [genericError] from the registry as fallback
  ///
  /// Example:
  /// ```dart
  /// final result = await SupabaseNetworkHandler.safeCall(
  ///   () => supabase.from('users').select().eq('id', userId).single(),
  ///   onError: (error) {
  ///     // Custom handling for specific cases
  ///     if (error is PostgrestException && error.code == 'PGRST116') {
  ///       return const Left(UserNotFoundFailure());
  ///     }
  ///     return null; // Fall through to registry
  ///   },
  /// );
  /// ```
  static Future<Either<Failure, T>> safeCall<T>(
    Future<T> Function() request, {
    Either<Failure, T>? Function(Object error)? onError,
  }) async {
    assert(
      _errorRegistry != null,
      'Supabase error registry must be set before calling safeCall. '
      'Call SupabaseNetworkHandler.setErrorRegistry() at app startup.',
    );

    try {
      final result = await request();
      return Right(result);
    } on AuthException catch (e, stackTrace) {
      _logError(e, stackTrace);
      return _handleAuthException<T>(e, onError);
    } on PostgrestException catch (e, stackTrace) {
      _logError(e, stackTrace);
      return _handlePostgrestException<T>(e, onError);
    } on StorageException catch (e, stackTrace) {
      _logError(e, stackTrace);
      return _handleStorageException<T>(e, onError);
    } on FunctionException catch (e, stackTrace) {
      _logError(e, stackTrace);
      return _handleFunctionException<T>(e, onError);
    } catch (e, stackTrace) {
      _logError(e, stackTrace);
      return _handleGeneralException<T>(e, onError);
    }
  }

  /// Handles AuthException errors (authentication/authorization failures)
  static Either<Failure, T> _handleAuthException<T>(
    AuthException exception,
    Either<Failure, T>? Function(Object error)? onError,
  ) {
    // Try custom error handler first
    if (onError != null) {
      final customResult = onError(exception);
      if (customResult != null) return customResult;
    }

    // Try auth error registry using the status code as error code
    final errorCode = exception.statusCode ?? exception.message;
    if (errorCode != null) {
      final authFailureFactory =
          _errorRegistry!.authErrorRegistry[errorCode];
      if (authFailureFactory != null) {
        return Left(authFailureFactory(exception));
      }
    }

    // Try general error registry
    final generalFactory =
        _errorRegistry!.generalErrorRegistry[exception.runtimeType];
    if (generalFactory != null) {
      return Left(generalFactory(exception));
    }

    return Left(_errorRegistry!.genericError);
  }

  /// Handles PostgrestException errors (database/REST API failures)
  static Either<Failure, T> _handlePostgrestException<T>(
    PostgrestException exception,
    Either<Failure, T>? Function(Object error)? onError,
  ) {
    // Try custom error handler first
    if (onError != null) {
      final customResult = onError(exception);
      if (customResult != null) return customResult;
    }

    // Try error code registry first (more specific)
    if (exception.code != null) {
      final codeFactory =
          _errorRegistry!.postgrestErrorCodeRegistry[exception.code];
      if (codeFactory != null) {
        final either = codeFactory(
          exception,
          exception.message,
          int.tryParse(exception.code ?? ''),
        );
        return either.fold(
          (failure) => Left<Failure, T>(failure),
          (success) => Right<Failure, T>(success as T),
        );
      }
    }

    // Try status code registry
    final statusCode = int.tryParse(exception.code ?? '');
    if (statusCode != null) {
      final statusFactory =
          _errorRegistry!.postgrestStatusRegistry[statusCode];
      if (statusFactory != null) {
        final either = statusFactory(
          exception,
          exception.message,
          statusCode,
        );
        return either.fold(
          (failure) => Left<Failure, T>(failure),
          (success) => Right<Failure, T>(success as T),
        );
      }
    }

    // Try general error registry
    final generalFactory =
        _errorRegistry!.generalErrorRegistry[exception.runtimeType];
    if (generalFactory != null) {
      return Left(generalFactory(exception));
    }

    return Left(_errorRegistry!.genericError);
  }

  /// Handles StorageException errors (file storage failures)
  static Either<Failure, T> _handleStorageException<T>(
    StorageException exception,
    Either<Failure, T>? Function(Object error)? onError,
  ) {
    // Try custom error handler first
    if (onError != null) {
      final customResult = onError(exception);
      if (customResult != null) return customResult;
    }

    // Try storage error registry
    final storageFactory =
        _errorRegistry!.storageErrorRegistry[exception.message];
    if (storageFactory != null) {
      return Left(storageFactory(exception));
    }

    // Try general error registry
    final generalFactory =
        _errorRegistry!.generalErrorRegistry[exception.runtimeType];
    if (generalFactory != null) {
      return Left(generalFactory(exception));
    }

    return Left(_errorRegistry!.genericError);
  }

  /// Handles FunctionException errors (Edge Function failures)
  static Either<Failure, T> _handleFunctionException<T>(
    FunctionException exception,
    Either<Failure, T>? Function(Object error)? onError,
  ) {
    // Try custom error handler first
    if (onError != null) {
      final customResult = onError(exception);
      if (customResult != null) return customResult;
    }

    // Try function error registry using status code
    final statusCode = exception.status;
    if (statusCode != null) {
      final functionFactory =
          _errorRegistry!.functionErrorRegistry[statusCode];
      if (functionFactory != null) {
        return Left(functionFactory(exception));
      }
    }

    // Try general error registry
    final generalFactory =
        _errorRegistry!.generalErrorRegistry[exception.runtimeType];
    if (generalFactory != null) {
      return Left(generalFactory(exception));
    }

    return Left(_errorRegistry!.genericError);
  }

  /// Handles general/unknown exceptions
  static Either<Failure, T> _handleGeneralException<T>(
    Object exception,
    Either<Failure, T>? Function(Object error)? onError,
  ) {
    // Try custom error handler first
    if (onError != null) {
      final customResult = onError(exception);
      if (customResult != null) return customResult;
    }

    // Try realtime error handler
    final realtimeFailure = _errorRegistry!.handleRealtimeError(exception);
    if (realtimeFailure != null) {
      return Left(realtimeFailure);
    }

    // Try general error registry
    final generalFactory =
        _errorRegistry!.generalErrorRegistry[exception.runtimeType];
    if (generalFactory != null) {
      return Left(generalFactory(exception));
    }

    return Left(_errorRegistry!.genericError);
  }
}
