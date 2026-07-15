/// Supabase integration for simple_network_handler.
///
/// This library provides error handling utilities specifically designed for
/// Supabase operations, following the same patterns as the core
/// simple_network_handler package.
///
/// Usage:
/// ```dart
/// import 'package:simple_network_handler/simple_network_handler_supabase.dart';
///
/// // Create your error registry
/// class MySupabaseErrorRegistry extends SupabaseErrorRegistry {
///   @override
///   SupabaseAuthErrorRegistry get authErrorRegistry => {
///     'invalid_credentials': (e) => const InvalidCredentialsFailure(),
///   };
///
///   @override
///   Failure get genericError => const GenericSupabaseFailure();
/// }
///
/// // Initialize at app startup
/// void main() {
///   SupabaseNetworkHandler.setErrorRegistry(MySupabaseErrorRegistry());
///   runApp(MyApp());
/// }
///
/// // Use in repositories
/// Future<Either<Failure, User>> getCurrentUser() {
///   return SupabaseNetworkHandler.safeCall(
///     () => supabase.auth.getUser(),
///   );
/// }
/// ```
library;

// Re-export core types needed for Supabase integration
export 'package:dartz/dartz.dart' show Either, Left, Right;
export 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthException,
        PostgrestException,
        StorageException,
        FunctionException;

// Export core failure class + the transport-aware fold helper
export 'src/failure.dart';
export 'src/map_business_extension.dart';

// Export Supabase-specific components
export 'src/supabase_error_registry.dart';
export 'src/supabase_failure.dart';
export 'src/supabase_network_handler.dart';
