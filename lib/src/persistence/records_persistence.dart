import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/mixpanel_record.dart';
import '../records_controller.dart';
import 'key_value_store.dart';

/// Saves the records and the toolbar state, so that they survive a page reload.
///
/// DevTools reloads the extension page on each hot restart of the app. Without this class the
/// tab would lose all records from earlier runs.
///
/// - [store] holds the records and the recording state of each app (its VM service URI).
/// - [preferences] holds the display modes. They apply to all apps, so they come back at once.
class RecordsPersistence {
  RecordsPersistence({required this.store, required this.preferences, required this.controller, this.maxSaved = 1000}) {
    _restorePreferences();
    controller.addListener(_onChanged);
  }

  final KeyValueStore store;
  final KeyValueStore preferences;
  final RecordsController controller;

  /// The number of most recent records to save.
  final int maxSaved;

  String? _key;
  String? _lastSavedRecords;
  String? _lastSavedPreferences;

  static const preferencesKey = 'mixpanel_devtools:preferences';

  static String storageKey(String appKey) => 'mixpanel_devtools:$appKey';

  /// Restores the saved records of the app that [appKey] identifies, then saves each change.
  void attach(String appKey) {
    final key = storageKey(appKey);
    if (_key == key) {
      return;
    }
    _key = key;
    _restoreRecords(key);
    _onChanged();
  }

  void dispose() => controller.removeListener(_onChanged);

  void _restorePreferences() {
    final json = _readJson(preferences, preferencesKey);
    if (json == null) {
      return;
    }
    controller.restore(
      const [],
      showMixpanelProps: json['showMixpanelProps'] as bool?,
      showOtherCalls: json['showOtherCalls'] as bool?,
    );
  }

  void _restoreRecords(String key) {
    final json = _readJson(store, key);
    if (json == null) {
      return;
    }
    final records = json['records'];
    controller.restore([
      if (records is List)
        for (final record in records.whereType<Map<Object?, Object?>>()) MixpanelRecord.fromJson(record),
    ], recording: json['recording'] as bool?);
  }

  void _onChanged() {
    _lastSavedPreferences = _write(
      preferences,
      preferencesKey,
      jsonEncode({'showMixpanelProps': controller.showMixpanelProps, 'showOtherCalls': controller.showOtherCalls}),
      _lastSavedPreferences,
    );
    final key = _key;
    if (key == null) {
      return;
    }
    final records = controller.records;
    final start = records.length > maxSaved ? records.length - maxSaved : 0;
    _lastSavedRecords = _write(
      store,
      key,
      jsonEncode({
        'recording': controller.recording,
        'records': [for (final record in records.skip(start)) record.toJson()],
      }),
      _lastSavedRecords,
    );
  }

  /// Writes [value] if it differs from [lastSaved]. Returns the value that the store now holds.
  static String? _write(KeyValueStore target, String key, String value, String? lastSaved) {
    if (value == lastSaved) {
      return lastSaved;
    }
    try {
      target.write(key, value);
      return value;
    } on Object catch (error) {
      debugPrint('mixpanel_devtools: could not save $key: $error');
      return lastSaved;
    }
  }

  static Map<String, Object?>? _readJson(KeyValueStore source, String key) {
    try {
      final saved = source.read(key);
      if (saved == null) {
        return null;
      }
      return jsonDecode(saved) as Map<String, Object?>;
    } on Object catch (error) {
      debugPrint('mixpanel_devtools: ignored the saved value of $key: $error');
      return null;
    }
  }
}
