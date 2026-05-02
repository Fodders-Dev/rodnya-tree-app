import 'package:uuid/uuid.dart';

class ClientInstanceId {
  ClientInstanceId._();

  static String? _value;

  static String get current {
    return _value ??= const Uuid().v4();
  }
}
