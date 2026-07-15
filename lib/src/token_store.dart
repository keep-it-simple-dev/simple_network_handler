/// Abstract access token storage used by `RefreshTokenInterceptor`.
///
/// Implement this with your preferred storage solution (secure storage,
/// shared preferences, in-memory, ...). The package intentionally does not
/// depend on any storage implementation.
abstract class TokenStore {
  /// Returns the currently stored access token, or `null` when there is none.
  Future<String?> readAccessToken();

  /// Persists a newly obtained access token.
  Future<void> writeAccessToken(String token);
}
