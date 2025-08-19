import 'package:flutter/material.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

/// Example custom failure for when user is not found
class UserNotFoundFailure extends Failure {
  const UserNotFoundFailure();

  @override
  String getTitle(BuildContext context) {
    return 'User not found';
  }

  @override
  String getSubtitle(BuildContext context) {
    return 'The user you are looking for does not exist.';
  }
}

class GenericFailure extends Failure {
  const GenericFailure();

  @override
  String getTitle(BuildContext context) {
    return '';
  }
}

class ServerFailure extends Failure {
  const ServerFailure();

  @override
  String getTitle(BuildContext context) {
    return '';
  }
}

class TimeoutFailure extends Failure {
  const TimeoutFailure();

  @override
  String getTitle(BuildContext context) {
    return '';
  }
}

class NoInternetFailure extends Failure {
  const NoInternetFailure();

  @override
  String getTitle(BuildContext context) {
    return '';
  }
}
