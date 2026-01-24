import 'package:simple_network_handler/simple_network_handler_supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Example repository demonstrating Supabase integration with error handling.
///
/// This follows the same pattern as [ExampleRepositoryImpl] but uses
/// [SupabaseNetworkHandler] instead of [SimpleNetworkHandler].
abstract class ExampleSupabaseRepository {
  Future<Either<Failure, User?>> getCurrentUser();
  Future<Either<Failure, AuthResponse>> signInWithEmail(
      String email, String password);
  Future<Either<Failure, void>> signOut();
  Future<Either<Failure, List<Map<String, dynamic>>>> getUsers();
  Future<Either<Failure, Map<String, dynamic>>> getUserById(String id);
  Future<Either<Failure, Map<String, dynamic>>> createUser(
      Map<String, dynamic> userData);
  Future<Either<Failure, Map<String, dynamic>>> updateUser(
      String id, Map<String, dynamic> userData);
  Future<Either<Failure, void>> deleteUser(String id);
  Future<Either<Failure, String>> uploadFile(
      String bucket, String path, List<int> fileBytes);
  Future<Either<Failure, dynamic>> invokeFunction(
      String functionName, Map<String, dynamic> body);
}

/// Implementation of [ExampleSupabaseRepository] using [SupabaseNetworkHandler].
class ExampleSupabaseRepositoryImpl implements ExampleSupabaseRepository {
  final SupabaseClient _supabase;

  ExampleSupabaseRepositoryImpl(this._supabase);

  // ============================================================
  // Authentication Operations
  // ============================================================

  @override
  Future<Either<Failure, User?>> getCurrentUser() {
    return SupabaseNetworkHandler.safeCall(
      () async => _supabase.auth.currentUser,
    );
  }

  @override
  Future<Either<Failure, AuthResponse>> signInWithEmail(
    String email,
    String password,
  ) {
    return SupabaseNetworkHandler.safeCall(
      () => _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      ),
    );
  }

  @override
  Future<Either<Failure, void>> signOut() {
    return SupabaseNetworkHandler.safeCall(
      () => _supabase.auth.signOut(),
    );
  }

  // ============================================================
  // Database Operations (PostgREST)
  // ============================================================

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getUsers() {
    return SupabaseNetworkHandler.safeCall(
      () => _supabase.from('users').select(),
    );
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getUserById(String id) {
    return SupabaseNetworkHandler.safeCall(
      () => _supabase.from('users').select().eq('id', id).single(),
      // Optional: Custom error handling for specific cases
      onError: (error) {
        if (error is PostgrestException && error.code == 'PGRST116') {
          return const Left(UserNotFoundSupabaseFailure());
        }
        return null; // Fall through to registry
      },
    );
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> createUser(
    Map<String, dynamic> userData,
  ) {
    return SupabaseNetworkHandler.safeCall(
      () => _supabase.from('users').insert(userData).select().single(),
    );
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> updateUser(
    String id,
    Map<String, dynamic> userData,
  ) {
    return SupabaseNetworkHandler.safeCall(
      () => _supabase
          .from('users')
          .update(userData)
          .eq('id', id)
          .select()
          .single(),
    );
  }

  @override
  Future<Either<Failure, void>> deleteUser(String id) {
    return SupabaseNetworkHandler.safeCall(
      () => _supabase.from('users').delete().eq('id', id),
    );
  }

  // ============================================================
  // Storage Operations
  // ============================================================

  @override
  Future<Either<Failure, String>> uploadFile(
    String bucket,
    String path,
    List<int> fileBytes,
  ) {
    return SupabaseNetworkHandler.safeCall(
      () => _supabase.storage.from(bucket).uploadBinary(path, fileBytes),
    );
  }

  // ============================================================
  // Edge Functions
  // ============================================================

  @override
  Future<Either<Failure, dynamic>> invokeFunction(
    String functionName,
    Map<String, dynamic> body,
  ) {
    return SupabaseNetworkHandler.safeCall(
      () async {
        final response = await _supabase.functions.invoke(
          functionName,
          body: body,
        );
        return response.data;
      },
    );
  }
}
