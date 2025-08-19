# Simple Network Handler

<p align="center">
  <img src="https://img.shields.io/pub/v/simple_network_handler.svg" alt="Pub Version">
  <img src="https://img.shields.io/pub/likes/simple_network_handler" alt="Pub Likes">
  <img src="https://img.shields.io/pub/points/simple_network_handler" alt="Pub Points">
</p>

A Flutter package for handling network errors with error registry and automatic response mapping using Dio interceptor.

## Features

- ✅ Automatic HTTP response mapping to `Either<Failure, Success>`
- ✅ Endpoint-specific error handling
- ✅ Global fallback error mappings
- ✅ Dio exception handling (timeouts, connection errors)

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
    
    //All endpoints
    '*': {
      500: (json) => const Left(ServerFailure()),
      422: (json) => Left(ValidationFailure(json['message'])),
    },
    
    '/api/login': {
      401: (json) => const Left(UnauthorizedFailure()),
      201: (json) => Right(TokenResponse.fromJson(json)),
    }
  };

  //Fallback if no errors are matching in the registry
  @override
  Failure get genericError => const GenericFailure();

  @override
  DioErrorRegistry get dioRegistry => {
    DioExceptionType.connectionTimeout: const TimeoutFailure(),
  };
}
```

### 3. Setup Dio and SimpleNetworkHandler

```dart
final dio = Dio();
final errorRegistry = AppErrorRegistry();

// Add interceptor
dio.interceptors.add(ErrorMappingInterceptor(errorRegistry: errorRegistry));

// Setup SimpleNetworkHandler
SimpleNetworkHandler.setErrorRegistry(errorRegistry);
```

### 4. Make Safe Network Calls

```dart
Future<Either<Failure, User>> getUser(int id) async {
  return SimpleNetworkHandler.safeCall<User>(
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
3. **Result Extraction** → `SimpleNetworkHandler.safeCall` returns `Either<Failure, Success>`

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

- **`SimpleNetworkHandler`** - Static utility for safe network calls
- **`ErrorRegistry`** - Abstract base for error mapping configuration  
- **`ErrorMappingInterceptor`** - Dio interceptor for response processing
- **`Failure`** - Base failure class with Flutter context support

### Methods

- **`SimpleNetworkHandler.safeCall<T>()`** - Execute network call with error handling
- **`SimpleNetworkHandler.setErrorRegistry()`** - Set global error registry

## License

MIT