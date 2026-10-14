// Reference recorder for the mixpanel_devtools DevTools extension.
//
// Copy this file into your app. It has no dependency on mixpanel_devtools, so that package
// can stay a dev_dependency. Then wrap the instance that Mixpanel.init returns:
//
//   final mixpanel = await Mixpanel.init(token, trackAutomaticEvents: true);
//   final recorded = MixpanelDevtoolsRecorder.instrument(mixpanel, token: token);
//
// In release builds `instrument` returns `mixpanel` unchanged and records nothing.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

typedef PostEvent = void Function(String kind, Map<String, Object?> data);

/// Keeps a buffer of Mixpanel calls and sends each one to the Mixpanel tab in DevTools.
class MixpanelDevtoolsRecorder {
  MixpanelDevtoolsRecorder({String? runId, DateTime Function()? now, PostEvent? postEvent})
    : runId = runId ?? '${DateTime.now().microsecondsSinceEpoch}',
      _now = now ?? DateTime.now,
      _postEvent = postEvent ?? developer.postEvent;

  static const int protocolVersion = 1;
  static const String recordEventKind = 'mixpanel_devtools:record';
  static const String getRecordsMethod = 'ext.mixpanel_devtools.getRecords';
  static const String clearMethod = 'ext.mixpanel_devtools.clear';
  static const String flushMethod = 'ext.mixpanel_devtools.flush';
  static const int maxRecords = 1000;

  /// Returns a [RecordingMixpanel] for [token], or [mixpanel] unchanged in release builds.
  static Mixpanel instrument(Mixpanel mixpanel, {required String token}) {
    if (kReleaseMode) {
      return mixpanel;
    }
    return RecordingMixpanel(token, MixpanelDevtoolsRecorder());
  }

  /// Unique for each app run, so that the tab can tell runs apart after a hot restart.
  final String runId;
  final DateTime Function() _now;
  final PostEvent _postEvent;
  final ListQueue<Map<String, Object?>> _buffer = ListQueue();
  int _nextId = 1;

  /// The super properties that Mixpanel adds to each event, as far as the app has told it.
  Map<String, Object?> superProperties = {};

  /// The distinct id that Mixpanel uses, if known.
  String? distinctId;

  /// Called by the `flush` service extension.
  Future<void> Function()? onFlush;

  List<Map<String, Object?>> get records => List.unmodifiable(_buffer);

  void record(String kind, String name, {Map<String, Object?>? properties, Map<String, Object?>? groups}) {
    final data = <String, Object?>{
      'id': _nextId++,
      'runId': runId,
      'timestamp': _now().millisecondsSinceEpoch,
      'kind': kind,
      'name': name,
      'properties': _jsonSafeMap(properties ?? const {}),
      if (kind == 'track') 'superProperties': _jsonSafeMap(superProperties),
      if (distinctId != null) 'distinctId': distinctId,
      if (groups != null) 'groups': _jsonSafeMap(groups),
    };
    _buffer.addLast(data);
    while (_buffer.length > maxRecords) {
      _buffer.removeFirst();
    }
    _postEvent(recordEventKind, data);
  }

  void clear() => _buffer.clear();

  /// Makes this recorder answer the service extensions. A later recorder replaces it.
  void registerServiceExtensions() {
    _active = this;
    if (_registered) {
      return;
    }
    _registered = true;
    for (final method in [getRecordsMethod, clearMethod, flushMethod]) {
      developer.registerExtension(method, (method, _) async {
        final active = _active;
        if (active == null) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            'No Mixpanel recorder is active.',
          );
        }
        return active.handleServiceExtension(method);
      });
    }
  }

  @visibleForTesting
  Future<developer.ServiceExtensionResponse> handleServiceExtension(String method) async {
    switch (method) {
      case getRecordsMethod:
        return developer.ServiceExtensionResponse.result(jsonEncode({'version': protocolVersion, 'records': records}));
      case clearMethod:
        clear();
        return developer.ServiceExtensionResponse.result('{}');
      case flushMethod:
        await onFlush?.call();
        return developer.ServiceExtensionResponse.result('{}');
    }
    return developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      'Unknown method $method',
    );
  }

  static MixpanelDevtoolsRecorder? _active;
  static bool _registered = false;
}

/// A [Mixpanel] that records each call, then passes it to the plugin unchanged.
class RecordingMixpanel extends Mixpanel {
  RecordingMixpanel(super.token, this.recorder) : _people = RecordingPeople(token, recorder) {
    recorder
      ..onFlush = flush
      ..registerServiceExtensions();
    unawaited(_seed());
  }

  final MixpanelDevtoolsRecorder recorder;
  final RecordingPeople _people;

  Future<void> _seed() async {
    try {
      final seeded = await super.getSuperProperties();
      if (seeded != null) {
        recorder.superProperties = {
          for (final entry in seeded.entries) '${entry.key}': entry.value,
          ...recorder.superProperties,
        };
      }
      final id = await getDistinctId();
      recorder.distinctId ??= id;
    } on Object catch (error) {
      debugPrint('mixpanel_devtools: could not read the Mixpanel state: $error');
    }
  }

  @override
  Future<void> track(String eventName, {Map<String, dynamic>? properties}) {
    recorder.record('track', eventName, properties: properties);
    return super.track(eventName, properties: properties);
  }

  @override
  Future<void> trackWithGroups(String eventName, Map<String, dynamic> properties, Map<String, dynamic> groups) {
    recorder.record('track', eventName, properties: properties, groups: groups);
    return super.trackWithGroups(eventName, properties, groups);
  }

  @override
  void timeEvent(String eventName) {
    recorder.record('timing', 'timeEvent', properties: {'event': eventName});
    super.timeEvent(eventName);
  }

  @override
  Future<void> identify(String distinctId) {
    recorder.distinctId = distinctId;
    recorder.record('identity', 'identify', properties: {'distinct_id': distinctId});
    return super.identify(distinctId);
  }

  @override
  void alias(String alias, String distinctId) {
    recorder.record('identity', 'alias', properties: {'alias': alias, 'distinct_id': distinctId});
    super.alias(alias, distinctId);
  }

  @override
  Future<void> reset() async {
    recorder.record('identity', 'reset');
    recorder
      ..superProperties = {}
      ..distinctId = null;
    await super.reset();
    try {
      final id = await getDistinctId();
      recorder.distinctId ??= id;
    } on Object catch (error) {
      debugPrint('mixpanel_devtools: could not read the distinct id: $error');
    }
  }

  @override
  Future<void> registerSuperProperties(Map<String, dynamic> properties) {
    recorder.superProperties = {...recorder.superProperties, ...properties};
    recorder.record('super', 'register', properties: properties);
    return super.registerSuperProperties(properties);
  }

  @override
  Future<void> registerSuperPropertiesOnce(Map<String, dynamic> properties) {
    recorder.superProperties = {...properties, ...recorder.superProperties};
    recorder.record('super', 'register_once', properties: properties);
    return super.registerSuperPropertiesOnce(properties);
  }

  @override
  Future<void> unregisterSuperProperty(String propertyName) {
    recorder.superProperties = {...recorder.superProperties}..remove(propertyName);
    recorder.record('super', 'unregister', properties: {'property': propertyName});
    return super.unregisterSuperProperty(propertyName);
  }

  @override
  Future<void> clearSuperProperties() {
    recorder.superProperties = {};
    recorder.record('super', 'clear');
    return super.clearSuperProperties();
  }

  @override
  void optInTracking() {
    recorder.record('consent', 'optInTracking');
    super.optInTracking();
  }

  @override
  void optOutTracking() {
    recorder.record('consent', 'optOutTracking');
    super.optOutTracking();
  }

  @override
  Future<void> flush() {
    recorder.record('flush', 'flush');
    return super.flush();
  }

  @override
  void setGroup(String groupKey, dynamic groupID) {
    _recordGroup('setGroup', groupKey, groupID);
    super.setGroup(groupKey, groupID);
  }

  @override
  void addGroup(String groupKey, dynamic groupID) {
    _recordGroup('addGroup', groupKey, groupID);
    super.addGroup(groupKey, groupID);
  }

  @override
  void removeGroup(String groupKey, dynamic groupID) {
    _recordGroup('removeGroup', groupKey, groupID);
    super.removeGroup(groupKey, groupID);
  }

  @override
  void deleteGroup(String groupKey, dynamic groupID) {
    _recordGroup('deleteGroup', groupKey, groupID);
    super.deleteGroup(groupKey, groupID);
  }

  @override
  People getPeople() => _people;

  void _recordGroup(String name, String groupKey, Object? groupID) {
    recorder.record('group', name, properties: {'group_key': groupKey, 'group_id': groupID});
  }
}

/// A [People] that records each call, then passes it to the plugin unchanged.
class RecordingPeople extends People {
  RecordingPeople(super.token, this.recorder);

  final MixpanelDevtoolsRecorder recorder;

  @override
  void set(String prop, dynamic to) {
    recorder.record('people', r'$set', properties: {prop: to});
    super.set(prop, to);
  }

  @override
  void setOnce(String prop, dynamic to) {
    recorder.record('people', r'$set_once', properties: {prop: to});
    super.setOnce(prop, to);
  }

  @override
  void increment(String prop, double by) {
    recorder.record('people', r'$add', properties: {prop: by});
    super.increment(prop, by);
  }

  @override
  void append(String name, dynamic value) {
    recorder.record('people', r'$append', properties: {name: value});
    super.append(name, value);
  }

  @override
  void union(String name, List<dynamic> value) {
    recorder.record('people', r'$union', properties: {name: value});
    super.union(name, value);
  }

  @override
  void remove(String name, dynamic value) {
    recorder.record('people', r'$remove', properties: {name: value});
    super.remove(name, value);
  }

  @override
  void unset(String name) {
    recorder.record('people', r'$unset', properties: {'property': name});
    super.unset(name);
  }

  @override
  void trackCharge(double amount, {Map<String, dynamic>? properties}) {
    recorder.record('people', 'trackCharge', properties: {'amount': amount, ...?properties});
    super.trackCharge(amount, properties: properties);
  }

  @override
  void clearCharges() {
    recorder.record('people', 'clearCharges');
    super.clearCharges();
  }

  @override
  void deleteUser() {
    recorder.record('people', r'$delete');
    super.deleteUser();
  }
}

Map<String, Object?> _jsonSafeMap(Map<Object?, Object?> map) {
  return map.map((key, value) => MapEntry('$key', _jsonSafe(value)));
}

Object? _jsonSafe(Object? value) {
  if (value is double && !value.isFinite) {
    return '$value';
  }
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Map) {
    return _jsonSafeMap(value);
  }
  if (value is Iterable) {
    return value.map(_jsonSafe).toList();
  }
  return '$value';
}
