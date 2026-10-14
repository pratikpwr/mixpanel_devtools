import 'dart:convert';

import 'mixpanel_record.dart';

/// Where the value of a [PropertyRow] came from.
enum PropertySource {
  /// The app passed it in the call.
  event('event'),

  /// A super property that Mixpanel adds to each event.
  superProperty('super'),

  /// A value that Mixpanel itself adds, such as `time` and `distinct_id`.
  mixpanel('mixpanel');

  const PropertySource(this.label);

  final String label;
}

/// One row of the property table.
class PropertyRow {
  const PropertyRow({required this.key, required this.value, required this.source});

  final String key;
  final Object? value;
  final PropertySource source;

  /// Strings without quotes. Lists and maps as indented JSON.
  String get displayValue => formatPropertyValue(value);

  /// True for the rows that "Mixpanel props: Hidden" removes.
  bool get isMixpanelProp => source == PropertySource.mixpanel || key.startsWith(r'$') || key.startsWith('mp_');
}

const _indentedJson = JsonEncoder.withIndent('  ', _toEncodable);

Object? _toEncodable(Object? value) => value.toString();

String formatPropertyValue(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is Map || value is List) {
    return _indentedJson.convert(value);
  }
  return '$value';
}

/// Builds the property table for [record], in display order and without duplicate keys.
///
/// For a `track` record: the event properties, then the super properties that the event does
/// not override, then `time` and `distinct_id`. For other kinds: the properties, then
/// `distinct_id`.
List<PropertyRow> buildPropertyRows(MixpanelRecord record, {required bool showMixpanelProps}) {
  final rows = <String, PropertyRow>{};

  void addAll(Map<String, Object?>? values, PropertySource source) {
    values?.forEach((key, value) {
      rows.putIfAbsent(key, () => PropertyRow(key: key, value: value, source: source));
    });
  }

  addAll(record.properties, PropertySource.event);
  if (record.isTrack) {
    addAll(record.superProperties, PropertySource.superProperty);
    addAll({'time': _seconds(record.timestamp)}, PropertySource.mixpanel);
  }
  if (record.distinctId != null) {
    addAll({'distinct_id': record.distinctId}, PropertySource.mixpanel);
  }

  final all = rows.values.toList();
  if (showMixpanelProps) {
    return all;
  }
  return all.where((row) => !row.isMixpanelProp).toList();
}

String _seconds(DateTime timestamp) => (timestamp.millisecondsSinceEpoch / 1000).toStringAsFixed(2);
