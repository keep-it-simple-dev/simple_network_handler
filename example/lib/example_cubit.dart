import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:simple_network_handler/simple_network_handler.dart';
import 'package:simple_network_handler_example/models/example_models.dart';
import 'package:simple_network_handler_example/network/example_repository.dart';

/// Simple state for the example
class ExampleState {
  final ExampleStatus status;
  final UserResponse? user;
  final Failure? error;

  const ExampleState({
    this.status = ExampleStatus.initial,
    this.user,
    this.error,
  });

  ExampleState copyWith({
    ExampleStatus? status,
    UserResponse? user,
    Failure? error,
  }) {
    return ExampleState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error ?? this.error,
    );
  }
}

enum ExampleStatus {
  initial,
  loading,
  success,
  failure,
}

/// Simple cubit that loads a user by ID
@injectable
class ExampleCubit extends Cubit<ExampleState> {
  final ExampleRepository _repository;

  ExampleCubit(this._repository) : super(const ExampleState());

  Future<void> loadUser(int userId) async {
    emit(state.copyWith(status: ExampleStatus.loading));
    
    final result = await _repository.getUserById(userId);
    result.fold(
      (failure) => emit(state.copyWith(
        status: ExampleStatus.failure, 
        error: failure,
      )),
      (user) => emit(state.copyWith(
        status: ExampleStatus.success,
        user: user,
      )),
    );
  }
}