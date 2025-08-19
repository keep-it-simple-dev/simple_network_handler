import 'package:json_annotation/json_annotation.dart';

part 'example_models.g.dart';

/// Simple user response model
@JsonSerializable()
class UserResponse {
  final int id;
  final String name;
  final String email;

  const UserResponse({
    required this.id,
    required this.name,
    required this.email,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) =>
      _$UserResponseFromJson(json);

  Map<String, dynamic> toJson() => _$UserResponseToJson(this);
}