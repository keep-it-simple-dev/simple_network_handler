import 'package:simple_network_handler/simple_network_handler_supabase.dart';

/// Example Supabase paths for type-safe endpoint references
class SupabasePaths {
  static const String users = 'users';
  static const String posts = 'posts';
  static const String comments = 'comments';
}

/// Example error registry for Supabase integration.
///
/// This demonstrates how to map Supabase-specific errors to domain failures
/// following the same pattern as [ExampleErrorRegistry] for Dio.
class ExampleSupabaseErrorRegistry extends SupabaseErrorRegistry {
  @override
  SupabaseAuthErrorRegistry get authErrorRegistry => {
        // Authentication error codes
        // See: https://supabase.com/docs/reference/dart/auth-error-codes
        'invalid_credentials': (e) => const InvalidCredentialsFailure(),
        'user_not_found': (e) => const UserNotFoundSupabaseFailure(),
        'email_not_confirmed': (e) => const EmailNotConfirmedFailure(),
        'invalid_grant': (e) => const SessionExpiredFailure(),
        'session_expired': (e) => const SessionExpiredFailure(),
      };

  @override
  SupabaseErrorCodeRegistry get postgrestErrorCodeRegistry => {
        // PostgREST error codes
        // See: https://postgrest.org/en/stable/references/errors.html
        'PGRST116': (error, message, statusCode) =>
            const Left(RecordNotFoundFailure()),
        '23505': (error, message, statusCode) =>
            const Left(DuplicateEntryFailure()),
        '42501': (error, message, statusCode) =>
            const Left(PermissionDeniedFailure()),
      };

  @override
  SupabaseStatusCodeRegistry get postgrestStatusRegistry => {
        400: (error, message, statusCode) =>
            Left(PostgrestFailure(message: message, statusCode: statusCode)),
        401: (error, message, statusCode) =>
            const Left(SessionExpiredFailure()),
        403: (error, message, statusCode) =>
            const Left(PermissionDeniedFailure()),
        404: (error, message, statusCode) =>
            const Left(RecordNotFoundFailure()),
        409: (error, message, statusCode) =>
            const Left(DuplicateEntryFailure()),
        429: (error, message, statusCode) => const Left(RateLimitFailure()),
      };

  @override
  SupabaseStorageErrorRegistry get storageErrorRegistry => {
        'Bucket not found': (e) =>
            const StorageFailure(errorMessage: 'Storage bucket not found'),
        'Object not found': (e) => const FileNotFoundFailure(),
        'The resource already exists': (e) => const DuplicateEntryFailure(),
      };

  @override
  SupabaseFunctionErrorRegistry get functionErrorRegistry => {
        401: (e) => const SessionExpiredFailure(),
        403: (e) => const PermissionDeniedFailure(),
        404: (e) => const FunctionFailure(
            statusCode: 404, errorMessage: 'Function not found'),
        429: (e) => const RateLimitFailure(),
        500: (e) => const FunctionFailure(
            statusCode: 500, errorMessage: 'Internal function error'),
      };

  @override
  SupabaseGeneralErrorRegistry get generalErrorRegistry => {
        FormatException: (e) => const GenericSupabaseFailure(
            errorMessage: 'Invalid data format'),
        TypeError: (e) =>
            const GenericSupabaseFailure(errorMessage: 'Type error occurred'),
      };

  @override
  Failure get genericError => const GenericSupabaseFailure();

  @override
  Failure? handleRealtimeError(Object error) {
    // Handle realtime-specific errors if needed
    return const RealtimeFailure();
  }
}
