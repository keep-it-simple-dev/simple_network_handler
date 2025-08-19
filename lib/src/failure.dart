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
