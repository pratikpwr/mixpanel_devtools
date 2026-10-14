import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_devtools/src/models/mixpanel_record.dart';
import 'package:mixpanel_devtools/src/models/property_row.dart';

MixpanelRecord _track({
  Map<String, Object?> properties = const {},
  Map<String, Object?>? superProperties,
  String? distinctId,
}) {
  return MixpanelRecord.fromJson({
    'id': 1,
    'runId': 'run',
    'timestamp': 1791444276820,
    'kind': 'track',
    'name': 'Item Viewed',
    'properties': properties,
    if (superProperties != null) 'superProperties': superProperties,
    if (distinctId != null) 'distinctId': distinctId,
  });
}

List<String> _keys(List<PropertyRow> rows) => rows.map((row) => row.key).toList();

void main() {
  group('buildPropertyRows for a track record', () {
    test('lists event, then super, then mixpanel rows when mixpanel props are shown', () {
      final rows = buildPropertyRows(
        _track(
          properties: {'screen': 'home'},
          superProperties: {
            'feature_flags': ['a: true'],
          },
          distinctId: 'user-1',
        ),
        showMixpanelProps: true,
      );

      expect(_keys(rows), ['screen', 'feature_flags', 'time', 'distinct_id']);
      expect(rows.map((row) => row.source), [
        PropertySource.event,
        PropertySource.superProperty,
        PropertySource.mixpanel,
        PropertySource.mixpanel,
      ]);
    });

    test('an event property overrides a super property with the same key', () {
      final rows = buildPropertyRows(
        _track(properties: {'plan': 'event value'}, superProperties: {'plan': 'super value', 'tier': 'gold'}),
        showMixpanelProps: false,
      );

      expect(_keys(rows), ['plan', 'tier']);
      expect(rows.first.value, 'event value');
      expect(rows.first.source, PropertySource.event);
    });

    test(r'hidden mode drops mixpanel rows and keys that start with $ or mp_', () {
      final rows = buildPropertyRows(
        _track(
          properties: {'screen': 'home', r'$os': 'iOS', 'mp_lib': 'flutter'},
          superProperties: {r'$app_version': '1.0', 'tier': 'gold'},
          distinctId: 'user-1',
        ),
        showMixpanelProps: false,
      );

      expect(_keys(rows), ['screen', 'tier']);
    });

    test('time is in seconds with two decimals', () {
      final rows = buildPropertyRows(_track(), showMixpanelProps: true);

      expect(rows.singleWhere((row) => row.key == 'time').displayValue, '1791444276.82');
    });

    test('distinct_id is left out when it is unknown', () {
      final rows = buildPropertyRows(_track(), showMixpanelProps: true);

      expect(_keys(rows), ['time']);
    });
  });

  group('buildPropertyRows for other kinds', () {
    test('shows the properties and the distinct id, with no super rows and no time', () {
      final record = MixpanelRecord.fromJson({
        'kind': 'people',
        'name': r'$set',
        'properties': {'company_name': 'Acme'},
        'superProperties': {'tier': 'gold'},
        'distinctId': 'user-1',
      });

      final rows = buildPropertyRows(record, showMixpanelProps: true);

      expect(_keys(rows), ['company_name', 'distinct_id']);
    });
  });

  group('PropertyRow.displayValue', () {
    PropertyRow row(Object? value) => PropertyRow(key: 'k', value: value, source: PropertySource.event);

    test('shows a string without quotes', () {
      expect(row('Plain text').displayValue, 'Plain text');
    });

    test('shows numbers, booleans, and null as text', () {
      expect(row(3).displayValue, '3');
      expect(row(false).displayValue, 'false');
      expect(row(null).displayValue, 'null');
    });

    test('shows lists and maps as indented JSON', () {
      expect(row(['a', 1]).displayValue, '[\n  "a",\n  1\n]');
      expect(row({'a': true}).displayValue, '{\n  "a": true\n}');
    });

    test('falls back to toString for values that JSON cannot encode', () {
      expect(row([_Opaque()]).displayValue, '[\n  "opaque"\n]');
    });
  });
}

class _Opaque {
  @override
  String toString() => 'opaque';
}
