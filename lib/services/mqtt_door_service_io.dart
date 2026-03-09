import 'dart:async';
import 'dart:convert';

import 'package:ahbu/models/door_record.dart';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

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

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _messageSub;

  bool _connecting = false;
  bool _connected = false;
  bool _sending = false;
  String? _lastError;
  final Map<String, bool?> _doorLocked = <String, bool?>{};
  final Map<String, String?> _doorEvents = <String, String?>{};
  final Map<String, DateTime?> _doorUpdatedAt = <String, DateTime?>{};
  final Set<String> _subscribedTopics = <String>{};
  final Map<String, _DoorWatchTarget> _targets = <String, _DoorWatchTarget>{};

  bool get connecting => _connecting;
  bool get connected => _connected;
  bool get sending => _sending;
  bool get commandEnabled => _connected && !_sending;
  String? get lastError => _lastError;

  Future<void> connect() async {
    if (_connected || _connecting) {
      return;
    }

    _connecting = true;
    _lastError = null;
    notifyListeners();

    try {
      final client = MqttServerClient.withPort(
        host,
        'ahbu-app-${DateTime.now().millisecondsSinceEpoch}',
        port,
      );
      client.secure = true;
      client.keepAlivePeriod = 20;
      client.logging(on: false);
      client.autoReconnect = true;
      client.resubscribeOnAutoReconnect = true;
      client.onConnected = _onConnected;
      client.onDisconnected = _onDisconnected;
      client.onAutoReconnect = _onAutoReconnect;
      client.onAutoReconnected = _onAutoReconnected;
      client.connectionMessage = MqttConnectMessage()
          .authenticateAs(username, password)
          .withClientIdentifier(
            'ahbu-app-${DateTime.now().millisecondsSinceEpoch}',
          )
          .withWillQos(MqttQos.atLeastOnce)
          .startClean();

      _client = client;
      await client.connect();

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception('MQTT baglanti hatasi: ${client.connectionStatus?.state}');
      }

      _messageSub?.cancel();
      _messageSub = client.updates?.listen(_onMessage);
      _connected = true;
      _lastError = null;
      await _resubscribeTrackedTopics();
    } catch (error) {
      _connected = false;
      _lastError = 'MQTT baglanamadi: $error';
      _safeDisconnect();
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> watchDoors(Iterable<DoorRecord> doors) async {
    final nextTargets = <String, _DoorWatchTarget>{};
    for (final door in doors) {
      final mqttSiteId = door.mqttSiteId;
      if (mqttSiteId == null || door.doorIndex <= 0) {
        continue;
      }
      final key = _doorKey(mqttSiteId, door.doorIndex);
      nextTargets[key] = _DoorWatchTarget(
        mqttSiteId: mqttSiteId,
        doorIndex: door.doorIndex,
      );
    }

    _targets
      ..clear()
      ..addAll(nextTargets);

    if (_targets.isEmpty) {
      notifyListeners();
      return;
    }

    await connect();
    await _resubscribeTrackedTopics();
  }

  Future<String?> sendPulseCommand({
    required int mqttSiteId,
    required int doorIndex,
    required String requestedBy,
  }) async {
    if (!_connected) {
      await connect();
    }

    final client = _client;
    if (!_connected || client == null) {
      return _lastError ?? 'MQTT baglantisi kurulamadi.';
    }

    _sending = true;
    _lastError = null;
    notifyListeners();

    try {
      final payload = jsonEncode({
        'action': 'pulse',
        'requested_by': requestedBy,
        'requested_at': DateTime.now().toUtc().toIso8601String(),
      });
      final builder = MqttClientPayloadBuilder()..addString(payload);
      client.publishMessage(
        'site/$mqttSiteId/door/$doorIndex/cmd',
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: false,
      );
      return null;
    } catch (error) {
      _lastError = 'Komut gonderilemedi: $error';
      return _lastError;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  bool? doorLockedFor(DoorRecord door) {
    final mqttSiteId = door.mqttSiteId;
    if (mqttSiteId == null) {
      return null;
    }
    return _doorLocked[_doorKey(mqttSiteId, door.doorIndex)];
  }

  String? lastEventFor(DoorRecord door) {
    final mqttSiteId = door.mqttSiteId;
    if (mqttSiteId == null) {
      return null;
    }
    return _doorEvents[_doorKey(mqttSiteId, door.doorIndex)];
  }

  DateTime? lastUpdatedAtFor(DoorRecord door) {
    final mqttSiteId = door.mqttSiteId;
    if (mqttSiteId == null) {
      return null;
    }
    return _doorUpdatedAt[_doorKey(mqttSiteId, door.doorIndex)];
  }

  Future<void> _resubscribeTrackedTopics() async {
    final client = _client;
    if (!_connected || client == null) {
      return;
    }

    final desiredTopics = <String>{};
    for (final target in _targets.values) {
      desiredTopics.add(_stateTopic(target.mqttSiteId, target.doorIndex));
      desiredTopics.add(_eventTopic(target.mqttSiteId, target.doorIndex));
    }

    final currentTopics = Set<String>.from(_subscribedTopics);
    for (final topic in currentTopics.difference(desiredTopics)) {
      client.unsubscribe(topic);
      _subscribedTopics.remove(topic);
    }

    for (final topic in desiredTopics.difference(currentTopics)) {
      client.subscribe(topic, MqttQos.atLeastOnce);
      _subscribedTopics.add(topic);
    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final envelope in messages) {
      final payloadMessage = envelope.payload;
      if (payloadMessage is! MqttPublishMessage) {
        continue;
      }

      final topic = envelope.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        payloadMessage.payload.message,
      );
      final parsed = _parseTopic(topic);
      if (parsed == null) {
        continue;
      }

      final key = _doorKey(parsed.mqttSiteId, parsed.doorIndex);
      _doorUpdatedAt[key] = DateTime.now();

      if (parsed.kind == 'state') {
        _doorLocked[key] = _extractLockedState(payload);
      } else if (parsed.kind == 'event') {
        _doorEvents[key] = payload;
      }
    }

    notifyListeners();
  }

  _ParsedTopic? _parseTopic(String topic) {
    final match = RegExp(r'^site/(\d+)/door/(\d+)/(state|event)$').firstMatch(topic);
    if (match == null) {
      return null;
    }
    return _ParsedTopic(
      mqttSiteId: int.parse(match.group(1)!),
      doorIndex: int.parse(match.group(2)!),
      kind: match.group(3)!,
    );
  }

  bool? _extractLockedState(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic> && decoded['locked'] is bool) {
        return decoded['locked'] as bool;
      }
      if (decoded is Map && decoded['locked'] != null) {
        return decoded['locked'].toString().toLowerCase() == 'true';
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _doorKey(int mqttSiteId, int doorIndex) => '$mqttSiteId:$doorIndex';

  String _stateTopic(int mqttSiteId, int doorIndex) =>
      'site/$mqttSiteId/door/$doorIndex/state';

  String _eventTopic(int mqttSiteId, int doorIndex) =>
      'site/$mqttSiteId/door/$doorIndex/event';

  void _onConnected() {
    _connected = true;
    _lastError = null;
    notifyListeners();
  }

  void _onDisconnected() {
    _connected = false;
    notifyListeners();
  }

  void _onAutoReconnect() {
    _connecting = true;
    notifyListeners();
  }

  void _onAutoReconnected() {
    _connecting = false;
    _connected = true;
    _resubscribeTrackedTopics();
    notifyListeners();
  }

  void _safeDisconnect() {
    try {
      _client?.disconnect();
    } catch (_) {
      // no-op
    }
    _client = null;
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _safeDisconnect();
    super.dispose();
  }
}

class _DoorWatchTarget {
  const _DoorWatchTarget({
    required this.mqttSiteId,
    required this.doorIndex,
  });

  final int mqttSiteId;
  final int doorIndex;
}

class _ParsedTopic {
  const _ParsedTopic({
    required this.mqttSiteId,
    required this.doorIndex,
    required this.kind,
  });

  final int mqttSiteId;
  final int doorIndex;
  final String kind;
}
