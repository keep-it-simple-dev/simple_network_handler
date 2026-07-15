import 'package:simple_network_handler/simple_network_handler.dart';

/// Transport-aware mapping helpers for `Either<Failure, T>` results.
extension MapBusinessX<T> on Either<Failure, T> {
  /// Maps the success value while letting [TransportFailure]s pass through
  /// UNCHANGED; substitutes [ifBusinessError] for any other [Left] so
  /// feature-specific copy is preserved for real server errors.
  ///
  /// This replaces the `fold((_) => Left(FeatureFailure()), ...)` pattern,
  /// which discarded transport classification — an offline/timeout failure
  /// would be relabelled as a business failure and the UI could no longer tell
  /// "you're offline" apart from "the server rejected this". With [mapBusiness],
  /// connectivity failures keep their transport identity and can be surfaced
  /// consistently everywhere, while genuine server-side errors still get the
  /// caller's feature-specific [ifBusinessError].
  ///
  /// ```dart
  /// // Before:
  /// return result.fold(
  ///   (_) => const Left(ProfileFailure()),
  ///   (data) => Right(data.toDomain()),
  /// );
  ///
  /// // After:
  /// return result.mapBusiness(
  ///   const ProfileFailure(),
  ///   (data) => Right(data.toDomain()),
  /// );
  /// ```
  Either<Failure, R> mapBusiness<R>(
    Failure ifBusinessError,
    Either<Failure, R> Function(T data) onData,
  ) =>
      fold(
        (f) => f is TransportFailure ? Left(f) : Left(ifBusinessError),
        onData,
      );
}
