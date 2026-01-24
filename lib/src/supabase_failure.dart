import 'package:flutter/material.dart';
import 'package:simple_network_handler/simple_network_handler.dart';

/// Base class for Supabase-specific failures.
///
/// Extend this class to create domain-specific failures for your Supabase
/// integration while maintaining consistency with the existing failure pattern.
abstract class SupabaseFailure extends Failure {
  const SupabaseFailure();
}

/// Failure for authentication-related errors.
///
/// Common scenarios:
/// - Invalid credentials
/// - Session expired
/// - Email not confirmed
/// - Invalid refresh token
class AuthFailure extends SupabaseFailure {
  final String? errorCode;
  final String? errorMessage;

  const AuthFailure({this.errorCode, this.errorMessage});

  @override
  String getTitle(BuildContext context) => 'Authentication Error';

  @override
  String getSubtitle(BuildContext context) =>
      errorMessage ?? 'An authentication error occurred.';
}

/// Failure for invalid login credentials.
class InvalidCredentialsFailure extends SupabaseFailure {
  const InvalidCredentialsFailure();

  @override
  String getTitle(BuildContext context) => 'Invalid Credentials';

  @override
  String getSubtitle(BuildContext context) =>
      'The email or password you entered is incorrect.';
}

/// Failure for unverified email addresses.
class EmailNotConfirmedFailure extends SupabaseFailure {
  const EmailNotConfirmedFailure();

  @override
  String getTitle(BuildContext context) => 'Email Not Confirmed';

  @override
  String getSubtitle(BuildContext context) =>
      'Please verify your email address before signing in.';
}

/// Failure for expired or invalid sessions.
class SessionExpiredFailure extends SupabaseFailure {
  const SessionExpiredFailure();

  @override
  String getTitle(BuildContext context) => 'Session Expired';

  @override
  String getSubtitle(BuildContext context) =>
      'Your session has expired. Please sign in again.';
}

/// Failure for user not found scenarios.
class UserNotFoundSupabaseFailure extends SupabaseFailure {
  const UserNotFoundSupabaseFailure();

  @override
  String getTitle(BuildContext context) => 'User Not Found';

  @override
  String getSubtitle(BuildContext context) =>
      'No user found with the provided credentials.';
}

/// Failure for database/PostgREST errors.
///
/// Common scenarios:
/// - Row not found (PGRST116)
/// - Unique constraint violation
/// - Foreign key violation
/// - Permission denied
class PostgrestFailure extends SupabaseFailure {
  final String? code;
  final String? message;
  final int? statusCode;

  const PostgrestFailure({this.code, this.message, this.statusCode});

  @override
  String getTitle(BuildContext context) => 'Database Error';

  @override
  String getSubtitle(BuildContext context) =>
      message ?? 'A database error occurred.';
}

/// Failure for when a database row/record is not found.
class RecordNotFoundFailure extends SupabaseFailure {
  const RecordNotFoundFailure();

  @override
  String getTitle(BuildContext context) => 'Not Found';

  @override
  String getSubtitle(BuildContext context) =>
      'The requested record was not found.';
}

/// Failure for unique constraint violations (duplicate entries).
class DuplicateEntryFailure extends SupabaseFailure {
  const DuplicateEntryFailure();

  @override
  String getTitle(BuildContext context) => 'Duplicate Entry';

  @override
  String getSubtitle(BuildContext context) =>
      'A record with this information already exists.';
}

/// Failure for permission/authorization errors.
class PermissionDeniedFailure extends SupabaseFailure {
  const PermissionDeniedFailure();

  @override
  String getTitle(BuildContext context) => 'Permission Denied';

  @override
  String getSubtitle(BuildContext context) =>
      'You do not have permission to perform this action.';
}

/// Failure for storage-related errors.
///
/// Common scenarios:
/// - Bucket not found
/// - Object not found
/// - File too large
/// - Invalid file type
class StorageFailure extends SupabaseFailure {
  final String? errorMessage;

  const StorageFailure({this.errorMessage});

  @override
  String getTitle(BuildContext context) => 'Storage Error';

  @override
  String getSubtitle(BuildContext context) =>
      errorMessage ?? 'A storage error occurred.';
}

/// Failure for when a file/object is not found in storage.
class FileNotFoundFailure extends SupabaseFailure {
  const FileNotFoundFailure();

  @override
  String getTitle(BuildContext context) => 'File Not Found';

  @override
  String getSubtitle(BuildContext context) =>
      'The requested file was not found.';
}

/// Failure for Edge Function errors.
class FunctionFailure extends SupabaseFailure {
  final int? statusCode;
  final String? errorMessage;

  const FunctionFailure({this.statusCode, this.errorMessage});

  @override
  String getTitle(BuildContext context) => 'Function Error';

  @override
  String getSubtitle(BuildContext context) =>
      errorMessage ?? 'An error occurred while executing the function.';
}

/// Failure for realtime/websocket connection errors.
class RealtimeFailure extends SupabaseFailure {
  const RealtimeFailure();

  @override
  String getTitle(BuildContext context) => 'Realtime Error';

  @override
  String getSubtitle(BuildContext context) =>
      'An error occurred with the realtime connection.';
}

/// Generic Supabase failure for unhandled errors.
class GenericSupabaseFailure extends SupabaseFailure {
  final String? errorMessage;

  const GenericSupabaseFailure({this.errorMessage});

  @override
  String getTitle(BuildContext context) => 'Error';

  @override
  String getSubtitle(BuildContext context) =>
      errorMessage ?? 'An unexpected error occurred.';
}

/// Failure for rate limiting errors.
class RateLimitFailure extends SupabaseFailure {
  const RateLimitFailure();

  @override
  String getTitle(BuildContext context) => 'Too Many Requests';

  @override
  String getSubtitle(BuildContext context) =>
      'Please wait a moment before trying again.';
}

/// Failure for network connectivity issues.
class SupabaseNetworkFailure extends SupabaseFailure {
  const SupabaseNetworkFailure();

  @override
  String getTitle(BuildContext context) => 'Network Error';

  @override
  String getSubtitle(BuildContext context) =>
      'Please check your internet connection and try again.';
}
