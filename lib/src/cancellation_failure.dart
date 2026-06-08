import 'package:flutter/material.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

/// Failure type returned when a request is cancelled
class CancellationFailure extends Failure {
  /// Optional reason for cancellation
  final String? reason;

  const CancellationFailure({this.reason});

  @override
  String getTitle(BuildContext context) => 'Request Cancelled';

  @override
  String getSubtitle(BuildContext context) =>
      reason ?? 'The operation was cancelled';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CancellationFailure &&
          runtimeType == other.runtimeType &&
          reason == other.reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'CancellationFailure(reason: $reason)';
}
