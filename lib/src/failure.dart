import 'package:flutter/material.dart';

abstract class FailureAbstract implements Exception {
  const FailureAbstract();

  String getTitle(BuildContext context);

  String getSubtitle(BuildContext context);
}

class Failure extends FailureAbstract {
  const Failure();

  @override
  String getSubtitle(BuildContext context) {
    return '';
  }

  @override
  String getTitle(BuildContext context) {
    return '';
  }
}

/// Marker for failures representing a transport-level problem (the request
/// never reached the backend / backend unreachable) rather than a business
/// rule. Lets UIs and observers special-case connectivity once, regardless
/// of feature.
///
/// Because it mixes onto the shared [Failure] base, it is available to both
/// the Dio (REST) and Supabase variants of this package. Mix it onto any
/// failure that represents an offline / timeout / unreachable condition:
///
/// ```dart
/// class OfflineFailure extends Failure with TransportFailure {
///   const OfflineFailure();
/// }
/// ```
///
/// Consumers can then branch on it once — `if (failure is TransportFailure)` —
/// instead of checking for each feature's connectivity failure individually.
/// See [Either.mapBusiness] (in `map_business_extension.dart`) for a fold
/// helper that lets these failures pass through repository mappers unchanged.
mixin TransportFailure on Failure {}
