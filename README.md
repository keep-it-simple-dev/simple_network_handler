# Simple Network Handler - Complete Usage Guide

A Flutter package that simplifies network error handling with automatic HTTP response mapping to
`Either<Failure, Success>`.

What if you could handle all http errors from one single place? This package does exactly that, allowing you to achieve something like this:
```dart
  ErrorModelRegistry get endpointRegistry => {
  '*': {
    422: (json) => Left(InvalidDataResponseFailure.fromJson(json)),
    202: (json) => Left(ParameterRequiredResponse.fromJson(json)),
    500: (json) => Left(ServerFailure.fromJson(json)),
    504: (json) => Left(TimeoutFailure.fromJson(json)),
  },
  AccountApiPath.sendVerificationCode: {
    403: (json) => Left(CodeSendForbiddenFailure.fromJson(json)),
  },
  AccountApiPath.resendVerificationCode: {
    403: (json) => Left(ResendTimeErrorFailure.fromJson(json)),
  },
  AuthApiPath.login: {
    404: (json) => Left(UserNotFoundFailure.fromJson(json)),
    400: (json) => Left(IncorrectPasswordFailure.fromJson(json)),
  },
};

```

## 🚀 Features

- **Automatic Error Mapping**: HTTP status codes → Custom failure types
- **Endpoint-Specific Handling**: Different errors for different endpoints
- **Automatic Token Refresh**: Queued 401 handling with single-flight refresh and request replay
- **Dio Integration**: Built-in interceptors for seamless integration
- **Clean Architecture**: Perfect for repository pattern and dependency injection

## 📦 Installation

```yaml
dependencies:
  simple_network_handler: ^1.3.0
  dio: ^5.8.0+1

  ############################
  # For advanced usage (see examples below)
  retrofit: ^4.4.2
  flutter_bloc: ^9.1.1
  injectable: ^2.5.0
  json_annotation: ^4.9.0

dev_dependencies:
  build_runner: ^2.4.15
  retrofit_generator: ^9.2.0
  json_serializable: ^6.9.5
  injectable_generator: ^2.7.0
  ##########################
```

## 🚀 Quick Start

### 1. Create Custom Failure Classes

```dart
class UserNotFoundFailure extends Failure {
  const UserNotFoundFailure();

  @override
  String getTitle(BuildContext context) => 'User not found';

  @override
  String getSubtitle(BuildContext context) => 'The user does not exist.';
}
```

### 2. Set Up Error Registry

```dart
class MyErrorRegistry extends ErrorRegistry {
  @override
  ErrorModelRegistry get endpointRegistry =>
      {
        '*': {
          500: (json) => Left(ServerFailure.fromJson(json)),
        },
        '/api/users/{id}': {
          404: (json) => const Left(UserNotFoundFailure()),
        },
      };

  @override
  Failure get genericError => const NetworkFailure();

  @override
  DioErrorRegistry get dioRegistry =>
      {
        DioExceptionType.connectionError: const NoInternetFailure(),
        DioExceptionType.connectionTimeout: const TimeoutFailure(),
      };
}
```

### 3. Initialize in Main

```dart
void main() {
  SimpleNetworkHandler.setErrorRegistry(MyErrorRegistry());
  runApp(MyApp());
}
```

### 4. Configure Dio with Interceptor

```dart
main() {
  final dio = Dio();
  dio.interceptors.add(ErrorMappingInterceptor(errorRegistry: MyErrorRegistry()));
}
```

### 5. Make Safe Network Calls

```dart
Future<Either<Failure, User>> getUser(int id) async {
  return SimpleNetworkHandler.safeCall(
        () => apiClient.getUserById(id),
  );
}
```

---

## 🔐 Automatic Token Refresh

`RefreshTokenInterceptor` transparently refreshes an expired access token and replays the failed
request. It is built on Dio's `QueuedInterceptorsWrapper`, so concurrent 401s are queued while a
single refresh runs (single-flight) — queued requests are then replayed with the new token without
triggering additional refreshes.

### 1. Implement a Token Store

The package stays storage-agnostic — back this with secure storage, shared preferences, memory, etc.

```dart
class MyTokenStore implements TokenStore {
  final FlutterSecureStorage _storage;

  MyTokenStore(this._storage);

  @override
  Future<String?> readAccessToken() => _storage.read(key: 'access_token');

  @override
  Future<void> writeAccessToken(String token) =>
      _storage.write(key: 'access_token', value: token);
}
```

### 2. Wire the Interceptors (order matters!)

Add `RefreshTokenInterceptor` **before** `ErrorMappingInterceptor`, so the refresh runs before
error mapping turns the 401 into a `Failure`:

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));

dio.interceptors.addAll([
  // 1. Refresh first: recovers expired sessions before errors are mapped
  RefreshTokenInterceptor(
    tokenStore: MyTokenStore(storage),
    refreshToken: () async {
      // Perform the refresh on a separate bare Dio instance (no interceptors!)
      final response = await Dio().post(
        'https://api.example.com/auth/refresh',
        data: {'refresh_token': await readRefreshToken()},
      );
      return response.data['access_token'] as String?;
    },
    excludedPaths: ['/auth/login', '/auth/refresh'],
    onRefreshFailed: (error) {
      // Session can no longer be refreshed: force logout
    },
  ),
  // 2. Error mapping second: maps whatever is left (including unrecoverable 401s)
  ErrorMappingInterceptor(errorRegistry: MyErrorRegistry()),
]);
```

Alternatively, describe the refresh call declaratively with `RefreshRequest` — it is executed on a
separate bare Dio instance automatically:

```dart
RefreshTokenInterceptor(
  tokenStore: MyTokenStore(storage),
  refreshRequest: RefreshRequest(
    path: 'https://api.example.com/auth/refresh',
    buildData: () async => {'refresh_token': await readRefreshToken()},
    extractAccessToken: (response) =>
        (response.data as Map<String, dynamic>)['access_token'] as String?,
  ),
)
```

### Configuration

| Parameter                         | Default                          | Description                                                                                          |
|-----------------------------------|----------------------------------|------------------------------------------------------------------------------------------------------|
| `tokenStore`                      | required                         | Reads/persists the access token (storage-agnostic)                                                    |
| `refreshToken` / `refreshRequest` | exactly one required             | Callback returning the new token, or a declarative refresh request executed on a bare Dio instance    |
| `triggerStatusCodes`              | `[401]`                          | Response status codes that trigger a refresh                                                          |
| `excludedPaths`                   | `[]`                             | Paths that never trigger a refresh and never get the token header (refresh endpoint, public endpoints)|
| `applyHeader`                     | `Authorization: Bearer <token>`  | How the token is applied to outgoing requests                                                         |
| `onRefreshFailed`                 | –                                | Called when the refresh fails or returns `null` (force-logout hook), then the original error proceeds |
| `httpClient`                      | `Dio()`                          | Bare Dio instance (no interceptors) used for the refresh request and request replays                  |

### How It Works

1. Every request gets the current token from the `TokenStore` applied via `applyHeader`.
2. On a 401 (or any configured status), a single refresh runs — concurrent 401s are queued.
3. The new token is persisted, the original request is replayed with the new header, and the
   caller receives the replay response as if nothing happened.
4. Queued requests detect the token already changed and are replayed without another refresh.
5. If the refresh fails or returns `null`, `onRefreshFailed` fires and the original error is
   propagated — `ErrorMappingInterceptor` then maps it to a `Failure` as usual.

> ⚠️ Never run the refresh call through the Dio instance the interceptor is attached to: the
> queued interceptor would deadlock (dio issue #1612), and an interceptor-visible refresh call can
> cause infinite 401 loops. Use a bare Dio in your `refreshToken` callback, or use
> `RefreshRequest`, which does this for you.

---

## 📡 Transport failures / offline handling

Transport-level problems — the device is offline, the request timed out, or the
backend is unreachable — are fundamentally different from business errors. The
request never reached the server, so no feature-specific copy applies; the user
just needs to know they're offline. This package lets you classify and surface
connectivity **once**, regardless of feature.

### 1. Mark your offline failure

`TransportFailure` is a marker mixin on the shared `Failure` base, so it works
for both the Dio and Supabase variants:

```dart
class OfflineFailure extends Failure with TransportFailure {
  const OfflineFailure();

  @override
  String getTitle(BuildContext context) => 'You are offline';

  @override
  String getSubtitle(BuildContext context) =>
      'Check your internet connection and try again.';
}
```

### 2. Point the registry at it (Supabase)

Override `transportError` to return your offline failure. The default
implementation of `isTransportError` already covers `TimeoutException` and
`SocketException`, so nothing else is required:

```dart
class MySupabaseErrorRegistry extends SupabaseErrorRegistry {
  @override
  Failure get genericError => const GenericSupabaseFailure();

  // Returned whenever isTransportError(error) is true.
  @override
  Failure get transportError => const OfflineFailure();

  // Optional: widen the default (e.g. the http package's ClientException).
  @override
  bool isTransportError(Object error) =>
      super.isTransportError(error) || error is ClientException;
}
```

`safeCall` now returns `Left(OfflineFailure())` for connectivity errors
automatically — you no longer need to abuse `handleRealtimeError` to detect
them. (Precedence for unrecognized exceptions: `onError` → `handleRealtimeError`
→ `isTransportError`/`transportError` → general registry → `genericError`.)

### 3. Let transport failures pass through repository mappers

`mapBusiness` is a transport-aware `fold`: it maps the success value, lets any
`TransportFailure` pass through **unchanged**, and substitutes a
feature-specific failure for every other `Left`. This replaces the
`fold((_) => Left(FeatureFailure()), ...)` pattern, which threw away the
transport classification and relabelled "you're offline" as a business error:

```dart
// Before — an offline error becomes a generic ProfileFailure:
return result.fold(
  (_) => const Left(ProfileFailure()),
  (data) => Right(data.toProfile()),
);

// After — OfflineFailure survives; real server errors still get ProfileFailure:
return result.mapBusiness(
  const ProfileFailure(),
  (data) => Right(data.toProfile()),
);
```

The UI (or a global observer) can then branch on the marker once:

```dart
if (failure is TransportFailure) {
  showOfflineBanner();
} else {
  showError(failure.getTitle(context));
}
```

> Fully backward compatible: `transportError` defaults to `genericError`, and
> the transport check runs only after the existing `handleRealtimeError`
> consultation — existing registries behave identically until they opt in.

---

## 🏗️ Advanced Usage - Production Example

This section shows a complete production-ready implementation with clean architecture.

### File Structure

```
lib/example/
├── example_models.dart      # Data models with JSON serialization
├── example_failure.dart     # Custom failure classes
├── example_api.dart         # Retrofit API client
├── example_network_module.dart # Dio wiring: RefreshTokenInterceptor → ErrorMappingInterceptor
├── example_error_registry.dart # HTTP error → Failure mapping
├── example_repository.dart  # Business logic layer
└── example_cubit.dart       # State management
```

### Key Components

**1. API Client with Retrofit**

```dart
class ExampleApiPath {
  static const String getUserById = '/api/users/{id}';
}

@RestApi()
@singleton
abstract class ExampleApi {
  @GET(ExampleApiPath.getUserById)
  Future<UserResponse> getUserById(@Path('id') int id);
}
```

**2. Error Registry with Mappings**

```dart
class ExampleErrorRegistry extends ErrorRegistry {
  @override
  ErrorModelRegistry get endpointRegistry =>
      {
        '*': {
          500: (json) => Left(ServerFailure.fromJson(json)),
        },
        ExampleApiPath.getUserById: {
          404: (json) => const Left(UserNotFoundFailure()),
        },
      };
}
```

**3. Repository with Safe Calls**

```dart
@Singleton(as: ExampleRepository)
class ExampleRepositoryImpl implements ExampleRepository {
  @override
  Future<Either<Failure, UserResponse>> getUserById(int id) async {
    return SimpleNetworkHandler.safeCall(() => _apiClient.getUserById(id));
  }
}
```

**4. Cubit State Management**

```dart
Future<void> loadUser(int userId) async {
  emit(state.copyWith(status: ExampleStatus.loading));

  final result = await _repository.getUserById(userId);
  result.fold(
        (failure) => emit(state.copyWith(status: ExampleStatus.failure, error: failure)),
        (user) => emit(state.copyWith(status: ExampleStatus.success, user: user)),
  );
}
```

### Custom Endpoint Logic

```dart
requestExample() {
  SimpleNetworkHandler.safeCall(
        () => _apiClient.getUserById(id), onEndpointError: (error) {
    if (error.response?.statusCode == 403) {
      // Custom logic here
    }
    return null; // Let registry handle it
  },
  );
}

```