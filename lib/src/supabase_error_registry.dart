import 'dart:async';

import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Factory function that creates an Either from a Supabase error
typedef SupabaseEitherFactory = Either<Failure, dynamic> Function(
  Object error,
  String? message,
  int? statusCode,
);

/// Registry mapping Supabase error codes to failure factories
/// Key is the error code string (e.g., 'PGRST116', 'invalid_credentials')
typedef SupabaseErrorCodeRegistry = Map<String, SupabaseEitherFactory>;

/// Registry mapping PostgrestException status codes to failure factories
typedef SupabaseStatusCodeRegistry = Map<int, SupabaseEitherFactory>;

/// Registry mapping AuthException error codes to failure factories
typedef SupabaseAuthErrorRegistry = Map<String, Failure Function(AuthException exception)>;

/// Registry mapping StorageException error codes to failure factories
typedef SupabaseStorageErrorRegistry = Map<String, Failure Function(StorageException exception)>;

/// Registry mapping FunctionException status codes to failure factories
typedef SupabaseFunctionErrorRegistry = Map<int, Failure Function(FunctionException exception)>;

/// Registry mapping general exception types to failures
typedef SupabaseGeneralErrorRegistry = Map<Type, Failure Function(Object exception)>;

/// Abstract error registry for Supabase-specific error handling
///
/// Implement this class to provide custom error mappings for your Supabase
/// integration. This follows the same pattern as [ErrorRegistry] for Dio.
///
/// Example:
/// ```dart
/// class MySupabaseErrorRegistry extends SupabaseErrorRegistry {
///   @override
///   SupabaseAuthErrorRegistry get authErrorRegistry => {
///     'invalid_credentials': (e) => const InvalidCredentialsFailure(),
///     'user_not_found': (e) => const UserNotFoundFailure(),
///   };
///
///   @override
///   SupabaseStatusCodeRegistry get postgrestStatusRegistry => {
///     404: (error, message, statusCode) => const Left(NotFoundFailure()),
///     409: (error, message, statusCode) => const Left(ConflictFailure()),
///   };
///
///   @override
///   Failure get genericError => const GenericSupabaseFailure();
/// }
/// ```
abstract class SupabaseErrorRegistry {
  /// Returns the mapping for PostgrestException error codes to failures
  ///
  /// Error codes are strings like 'PGRST116' (for "no rows returned")
  /// See: https://postgrest.org/en/stable/references/errors.html
  SupabaseErrorCodeRegistry get postgrestErrorCodeRegistry => {};

  /// Returns the mapping for PostgrestException HTTP status codes to failures
  ///
  /// Common status codes: 400, 401, 403, 404, 409, 500, etc.
  SupabaseStatusCodeRegistry get postgrestStatusRegistry => {};

  /// Returns the mapping for AuthException errors to failures.
  ///
  /// Keys are matched against the [AuthException] in priority order:
  /// 1. `code` — the semantic error code, e.g. 'invalid_credentials',
  ///    'user_not_found', 'email_not_confirmed', 'invalid_grant'.
  /// 2. `statusCode` — the numeric HTTP status as a string, e.g. '400', '422'.
  /// 3. `message` — the raw human-readable message.
  ///
  /// Prefer keying by `code`; fall back to `statusCode`/`message` only for
  /// errors that do not carry a semantic code.
  /// See: https://supabase.com/docs/reference/dart/auth-error-codes
  SupabaseAuthErrorRegistry get authErrorRegistry => {};

  /// Returns the mapping for StorageException error codes to failures
  ///
  /// Common error codes: 'Bucket not found', 'Object not found', etc.
  SupabaseStorageErrorRegistry get storageErrorRegistry => {};

  /// Returns the mapping for FunctionException status codes to failures
  ///
  /// Maps Edge Function HTTP response status codes to failures
  SupabaseFunctionErrorRegistry get functionErrorRegistry => {};

  /// Returns the mapping for general exception types to failures
  ///
  /// Use this for handling non-Supabase exceptions like FormatException,
  /// TypeError, etc.
  SupabaseGeneralErrorRegistry get generalErrorRegistry => {};

  /// Returns the default failure for unhandled cases
  Failure get genericError;

  /// Optional: Override to provide custom handling for realtime errors
  Failure? handleRealtimeError(Object error) => null;

  /// The failure returned for a transport-level error (the request never
  /// reached the backend / the backend was unreachable) — see
  /// [isTransportError].
  ///
  /// Defaults to [genericError] so existing consumers behave identically
  /// without opting in. Override to return a dedicated (ideally localized)
  /// offline failure — preferably one that mixes in [TransportFailure] so UIs
  /// and observers can special-case connectivity once, regardless of feature:
  ///
  /// ```dart
  /// class OfflineFailure extends Failure with TransportFailure { ... }
  ///
  /// @override
  /// Failure get transportError => const OfflineFailure();
  /// ```
  Failure get transportError => genericError;

  /// Whether [error] represents a transport-level problem (the request never
  /// reached the backend / the backend was unreachable) rather than a business
  /// rule.
  ///
  /// The default covers [TimeoutException] (from `dart:async`) and
  /// `SocketException` (no connectivity / host unreachable). `SocketException`
  /// lives in `dart:io`, which this package deliberately does NOT import (that
  /// would break web compilation), so it is matched by runtime type name
  /// instead of `is`.
  ///
  /// Override to broaden or narrow the set — e.g. to also treat the `http`
  /// package's `ClientException` as a transport error:
  ///
  /// ```dart
  /// @override
  /// bool isTransportError(Object error) =>
  ///     super.isTransportError(error) || error is ClientException;
  /// ```
  bool isTransportError(Object error) {
    if (error is TimeoutException) return true;
    return error.runtimeType.toString() == 'SocketException';
  }
}
