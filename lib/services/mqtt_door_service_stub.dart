import 'package:ahbu/models/door_record.dart';
import 'package:flutter/foundation.dart';

class MqttDoorService extends ChangeNotifier {
  MqttDoorService({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  final String host;
  final int port;
  final String username;
  final String password;

  bool get connecting => false;
  bool get connected => false;
  bool get sending => false;
  bool get commandEnabled => false;
  String? get lastError => 'Bu platform MQTT TCP baglantisini desteklemiyor.';

  Future<void> connect() async {}

  Future<void> watchDoors(Iterable<DoorRecord> doors) async {}

  Future<String?> sendPulseCommand({
    required int mqttSiteId,
    required int doorIndex,
    required String requestedBy,
  }) async {
    return 'Bu platform MQTT TCP baglantisini desteklemiyor.';
  }

  bool? doorLockedFor(DoorRecord door) => null;

  String? lastEventFor(DoorRecord door) => null;

  DateTime? lastUpdatedAtFor(DoorRecord door) => null;
}
