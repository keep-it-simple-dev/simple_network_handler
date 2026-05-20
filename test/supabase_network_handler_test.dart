import 'package:flutter_test/flutter_test.dart';
import 'package:simple_network_handler/simple_network_handler_supabase.dart';

/// Failure that carries a label so tests can assert which registry entry
/// produced it.
class LabelFailure extends Failure {
  const LabelFailure(this.label);

  final String label;
}

/// Registry exercising auth lookups by `code`, `statusCode` and `message`.
class TestSupabaseRegistry extends SupabaseErrorRegistry {
  @override
  SupabaseAuthErrorRegistry get authErrorRegistry => {
        // Keyed by semantic code.
        'email_not_confirmed': (e) => const LabelFailure('by-code'),
        'invalid_credentials': (e) => const LabelFailure('by-code'),
        // Keyed by numeric status code (as a string).
        '429': (e) => const LabelFailure('by-status'),
        // Keyed by a raw message (legacy registries).
        'Legacy raw message': (e) => const LabelFailure('by-message'),
      };

  @override
  Failure get genericError => const LabelFailure('generic');
}

String _labelOf(Either<Failure, Object?> result) => result.fold(
      (failure) => (failure as LabelFailure).label,
      (_) => 'success',
    );

void main() {
  group('SupabaseNetworkHandler auth error resolution', () {
    setUp(() {
      SupabaseNetworkHandler.setErrorRegistry(TestSupabaseRegistry());
    });

    test('resolves failure by semantic code', () async {
      final result = await SupabaseNetworkHandler.safeCall<void>(
        () => throw const AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        ),
      );

      expect(result.isLeft(), true);
      expect(_labelOf(result), 'by-code');
    });

    test('falls back to status code when code is not registered', () async {
      final result = await SupabaseNetworkHandler.safeCall<void>(
        () => throw const AuthException(
          'Too many requests',
          statusCode: '429',
          code: 'over_request_rate_limit',
        ),
      );

      expect(_labelOf(result), 'by-status');
    });

    test('falls back to message when code and status are not registered',
        () async {
      final result = await SupabaseNetworkHandler.safeCall<void>(
        () => throw const AuthException('Legacy raw message'),
      );

      expect(_labelOf(result), 'by-message');
    });

    test('prefers code over status code and message', () async {
      // statusCode '429' is also registered, but code wins.
      final result = await SupabaseNetworkHandler.safeCall<void>(
        () => throw const AuthException(
          'Legacy raw message',
          statusCode: '429',
          code: 'invalid_credentials',
        ),
      );

      expect(_labelOf(result), 'by-code');
    });

    test('falls back to generic error when nothing matches', () async {
      final result = await SupabaseNetworkHandler.safeCall<void>(
        () => throw const AuthException(
          'Unmapped error',
          statusCode: '418',
          code: 'totally_unknown',
        ),
      );

      expect(_labelOf(result), 'generic');
    });

    test('onError callback takes priority over the registry', () async {
      final result = await SupabaseNetworkHandler.safeCall<void>(
        () => throw const AuthException(
          'Email not confirmed',
          code: 'email_not_confirmed',
        ),
        onError: (error) => const Left(LabelFailure('by-on-error')),
      );

      expect(_labelOf(result), 'by-on-error');
    });

    test('returns Right on success', () async {
      final result = await SupabaseNetworkHandler.safeCall<int>(
        () async => 42,
      );

      expect(result.isRight(), true);
      expect(result.getOrElse(() => -1), 42);
    });
  });
}
