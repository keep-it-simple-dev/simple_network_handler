# 1.3.0
  - feat: add `TransportFailure` marker mixin on the shared `Failure` base. Mix it onto any failure representing a transport-level problem (offline / timeout / unreachable) so UIs and observers can special-case connectivity once, regardless of feature. Because it lives on the shared base, it is available to both the Dio (REST) and Supabase variants.
  - feat: `SupabaseErrorRegistry` gains first-class transport classification — `bool isTransportError(Object error)` (default covers `TimeoutException` and `SocketException`; `SocketException` matched by runtime type name to avoid a `dart:io` import so web builds keep compiling) and `Failure get transportError` (defaults to `genericError`; override to return your localized offline failure). Wired into `safeCall`'s general-exception path.
  - feat: add `Either<Failure, T>.mapBusiness(ifBusinessError, onData)` extension — a transport-aware fold that lets `TransportFailure`s pass through unchanged while substituting a feature-specific failure for any other `Left`. Replaces the `fold((_) => Left(FeatureFailure()), ...)` pattern that discarded transport classification.
  - note: fully backward compatible. Existing consumers compile and behave identically without opting in — the default `transportError` is `genericError`, and the new transport check runs only AFTER the existing `handleRealtimeError` consultation, so registries that classify transport errors via the realtime hook keep working unchanged.
  - migration hint: replace `result.fold((_) => Left(FeatureFailure()), (data) => Right(...))` with `result.mapBusiness(const FeatureFailure(), (data) => Right(...))`, and override `transportError` on your registry to return a failure that mixes in `TransportFailure`.

# 1.2.0
  - feat: add RefreshTokenInterceptor with automatic token refresh, single-flight queuing of concurrent 401s and request replay
  - feat: add TokenStore interface and RefreshRequest spec executed on a separate bare Dio instance
  - docs: document the required interceptor order with ErrorMappingInterceptor

# 1.1.1
  - fix: `SupabaseNetworkHandler` now resolves `AuthException`s against the auth registry by semantic `code` (e.g. `email_not_confirmed`, `invalid_credentials`), falling back to `statusCode` and then `message`. Previously only `statusCode`/`message` were checked, so registries keyed by error codes never matched.

# 1.1.0
  - feat: add Supabase API support with `SupabaseNetworkHandler` and `SupabaseErrorRegistry`
  - feat: add Supabase-specific failure classes (AuthFailure, PostgrestFailure, StorageFailure, etc.)
  - feat: add separate import for Supabase: `import 'package:simple_network_handler/simple_network_handler_supabase.dart'`
  - feat: add example Supabase error registry and repository implementation

# 1.0.4
  - feat: change general error to accept types and provide access to the exception itself
  - feat: add logging functionality

# 1.0.3
  - feat: add handling of custom exceptions 

# 1.0.2
  - chore: update readme

# 1.0.1

  - chore: update readme
  - feat: add example app that showcases an advanced use case


# 1.0.0

  - feat: initial release of Simple Network Handler
