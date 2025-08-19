# Simple Network Handler - Complete Usage Guide

A Flutter package that simplifies network error handling with automatic HTTP response mapping to
`Either<Failure, Success>`.

## 🚀 Features

- **Automatic Error Mapping**: HTTP status codes → Custom failure types
- **Endpoint-Specific Handling**: Different errors for different endpoints
- **Dio Integration**: Built-in interceptors for seamless integration
- **Clean Architecture**: Perfect for repository pattern and dependency injection

## 📦 Installation

```yaml
dependencies:
  simple_network_handler: ^1.0.0
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

final dio = Dio();
dio.interceptors.add(ErrorMappingInterceptor(errorRegistry: MyErrorRegistry()));
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

## 🏗️ Advanced Usage - Production Example

This section shows a complete production-ready implementation with clean architecture.

### Architecture

```
UI Layer (Cubit/Bloc) → Repository → API Client (Retrofit)
     ↓                      ↓              ↓
Error Display ←── SimpleNetworkHandler ←── Error Registry
```

### File Structure

```
lib/example/
├── example_models.dart      # Data models with JSON serialization
├── example_failure.dart     # Custom failure classes
├── example_api.dart         # Retrofit API client
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
return SimpleNetworkHandler.safeCall(
() => _apiClient.getUserById(id),
onEndpointError: (error) {
if (error.response?.statusCode == 403) {
// Custom logic here
}
return null; // Let registry handle it
},
);
```