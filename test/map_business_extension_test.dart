import 'package:flutter_test/flutter_test.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

/// A transport-level failure (offline / timeout / unreachable).
class _OfflineFailure extends Failure with TransportFailure {
  const _OfflineFailure();
}

/// A plain server-side / business failure carried by a Left.
class _ServerFailure extends Failure {
  const _ServerFailure();
}

/// The feature-specific fallback substituted for non-transport Lefts.
class _FeatureFailure extends Failure {
  const _FeatureFailure();
}

void main() {
  group('Either.mapBusiness', () {
    test('lets a TransportFailure pass through unchanged', () {
      final Either<Failure, int> input = const Left(_OfflineFailure());

      final result = input.mapBusiness<String>(
        const _FeatureFailure(),
        (data) => Right('$data'),
      );

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<_OfflineFailure>()),
        (_) => fail('expected the transport failure to pass through'),
      );
    });

    test('substitutes ifBusinessError for a non-transport Left', () {
      final Either<Failure, int> input = const Left(_ServerFailure());

      final result = input.mapBusiness<String>(
        const _FeatureFailure(),
        (data) => Right('$data'),
      );

      result.fold(
        (failure) => expect(failure, isA<_FeatureFailure>()),
        (_) => fail('expected the business fallback'),
      );
    });

    test('maps a Right through onData', () {
      const Either<Failure, int> input = Right(21);

      final result = input.mapBusiness<int>(
        const _FeatureFailure(),
        (data) => Right(data * 2),
      );

      expect(result.isRight(), true);
      expect(result.getOrElse(() => -1), 42);
    });

    test('onData may itself return a Left', () {
      const Either<Failure, int> input = Right(1);

      final result = input.mapBusiness<int>(
        const _FeatureFailure(),
        (_) => const Left(_ServerFailure()),
      );

      result.fold(
        (failure) => expect(failure, isA<_ServerFailure>()),
        (_) => fail('expected onData to produce a Left'),
      );
    });
  });
}
