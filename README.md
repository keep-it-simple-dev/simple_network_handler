# Simple Network Handler

<p align="center">
  <img src="https://img.shields.io/pub/v/simple_network_handler.svg" alt="Pub Version">
  <img src="https://img.shields.io/pub/likes/simple_network_handler" alt="Pub Likes">
  <img src="https://img.shields.io/pub/points/simple_network_handler" alt="Pub Points">
</p>

A Flutter package for handling network errors with error registry and automatic response mapping using Dio interceptors.

## Features

- ✅ Automatic HTTP response mapping to `Either<Failure, Success>`
- ✅ Endpoint-specific error handling
- ✅ Global fallback error mappings
- ✅ Dio exception handling (timeouts, connection errors)
- ✅ Type-safe failure classes with Flutter context support

## Installation

```yaml
dependencies:
  simple_network_handler: ^1.0.0
  dio: ^5.8.0+1
```

## Usage

### 1. Create Failure Classes

```dart
class ValidationFailure extends Failure {
  final String message;
  const ValidationFailure(this.message);
  
  @override
  String getTitle(BuildContext context) => 'Validation Error';
  
  @override
  String getSubtitle(BuildContext context) => message;
}
```

### 2. Create Error Registry

```dart
class AppErrorRegistry extends ErrorRegistry {
  @override
  ErrorModelRegistry get endpointRegistry => {
    '/api/login': {
      401: (json) => const Left(UnauthorizedFailure()),
      200: (json) => Right(TokenResponse.fromJson(json)),
    },
    '*': {
      500: (json) => const Left(ServerFailure()),
      422: (json) => Left(ValidationFailure(json['message'])),
    },
  };

  @override
  Failure get genericError => const NetworkFailure();

  @override
  DioErrorRegistry get dioRegistry => {
    DioExceptionType.connectionTimeout: const TimeoutFailure(),
  };
}
```

### 3. Setup Dio and NetworkHandler

```dart
final dio = Dio();
final errorRegistry = AppErrorRegistry();

// Add interceptor
dio.interceptors.add(ErrorMappingInterceptor(errorRegistry: errorRegistry));

// Setup NetworkHandler
NetworkHandler.setErrorRegistry(errorRegistry);
```

### 4. Make Safe Network Calls

```dart
Future<Either<Failure, User>> getUser(int id) async {
  return NetworkHandler.safeNetworkCall<User>(
    () => dio.get('/api/users/$id'),
  );
}

// Handle the result
final result = await getUser(123);
result.fold(
  (failure) => print('Error: ${failure.getTitle(context)}'),
  (user) => print('Success: ${user.name}'),
);
```

## How It Works

1. **HTTP Request** → Dio makes the request
2. **Response Processing** → `ErrorMappingInterceptor` maps status codes using your registry
3. **Result Extraction** → `NetworkHandler.safeNetworkCall` returns `Either<Failure, Success>`

## Error Registry Mapping

### Endpoint-Specific
```dart
'/api/login': {
  401: (json) => const Left(UnauthorizedFailure()),
  200: (json) => Right(TokenResponse.fromJson(json)),
}
```

### Global Fallback
```dart
'*': {
  500: (json) => const Left(ServerFailure()),
}
```

### Dio Exceptions
```dart
DioErrorRegistry get dioRegistry => {
  DioExceptionType.connectionTimeout: const TimeoutFailure(),
};
```

## API Reference

### Classes

- **`NetworkHandler`** - Static utility for safe network calls
- **`ErrorRegistry`** - Abstract base for error mapping configuration  
- **`ErrorMappingInterceptor`** - Dio interceptor for response processing
- **`Failure`** - Base failure class with Flutter context support

### Methods

- **`NetworkHandler.safeNetworkCall<T>()`** - Execute network call with error handling
- **`NetworkHandler.setErrorRegistry()`** - Set global error registry

## License

MIT