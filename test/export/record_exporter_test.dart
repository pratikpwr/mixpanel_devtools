import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_devtools/src/export/record_exporter.dart';
import 'package:mixpanel_devtools/src/models/mixpanel_record.dart';

const _timestamp = 1791444276820;
const _isoTime = '2026-10-08T07:24:36.820Z';

MixpanelRecord _record({
  int id = 1,
  String kind = 'track',
  String name = 'Item Viewed',
  Map<String, Object?> properties = const {},
  Map<String, Object?>? superProperties,
}) {
  return MixpanelRecord.fromJson({
    'id': id,
    'runId': 'run',
    'timestamp': _timestamp,
    'kind': kind,
    'name': name,
    'properties': properties,
    if (superProperties != null) 'superProperties': superProperties,
    'distinctId': 'user-1',
  });
}

void main() {
  final hidden = RecordExporter(showMixpanelProps: false);
  final shown = RecordExporter(showMixpanelProps: true);

  group('toJson', () {
    test('writes event, kind, UTC ISO time, and the visible properties', () {
      final json = jsonDecode(
        hidden.toJson([
          _record(properties: {'screen': 'home'}, superProperties: {'tier': 'gold'}),
          _record(id: 2, kind: 'people', name: r'$set', properties: {'company_name': 'Acme'}),
        ]),
      );

      expect(json, [
        {
          'event': 'Item Viewed',
          'kind': 'track',
          'time': _isoTime,
          'properties': {'screen': 'home', 'tier': 'gold'},
        },
        {
          'event': r'$set',
          'kind': 'people',
          'time': _isoTime,
          'properties': {'company_name': 'Acme'},
        },
      ]);
    });

    test('adds the mixpanel properties when they are shown', () {
      final json = jsonDecode(shown.toJson([_record()])) as List<Object?>;

      expect((json.single as Map)['properties'], {'time': '1791444276.82', 'distinct_id': 'user-1'});
    });

    test('recordToJson writes one object', () {
      final json = jsonDecode(hidden.recordToJson(_record(properties: {'screen': 'home'})));

      expect(json, {
        'event': 'Item Viewed',
        'kind': 'track',
        'time': _isoTime,
        'properties': {'screen': 'home'},
      });
    });
  });

  group('toCsv', () {
    test('writes one row per record, with the union of keys in first-seen order', () {
      final csv = hidden.toCsv([
        _record(properties: {'screen': 'home', 'count': 2}),
        _record(id: 2, name: 'Button Clicked', properties: {'button': 'checkout', 'screen': 'cart'}),
      ]);

      expect(
        csv,
        '#,recorded_at,kind,event,screen,count,button\r\n'
        '1,$_isoTime,track,Item Viewed,home,2,\r\n'
        '2,$_isoTime,track,Button Clicked,cart,,checkout\r\n',
      );
    });

    test('quotes fields that hold commas, quotes, or line breaks', () {
      final csv = hidden.toCsv([
        _record(name: 'Viewed, again', properties: {'note': 'say "hi"\nnow'}),
      ]);

      expect(csv.split('\r\n')[1], '1,$_isoTime,track,"Viewed, again","say ""hi""\nnow"');
    });

    test('writes lists and maps as one-line JSON', () {
      final csv = hidden.toCsv([
        _record(
          properties: {
            'flags': ['a: true', 'b: false'],
          },
        ),
      ]);

      expect(csv.split('\r\n')[1], '1,$_isoTime,track,Item Viewed,"[""a: true"",""b: false""]"');
    });

    test('a property with the name of a fixed column gets its own header', () {
      final csv = shown.toCsv([
        _record(kind: 'timing', name: 'timeEvent', properties: {'event': 'Page Viewed', 'kind': 'x'}),
      ]);

      expect(csv.split('\r\n').first, '#,recorded_at,kind,event,property: event,property: kind,distinct_id');
      expect(csv.split('\r\n')[1], '1,$_isoTime,timing,timeEvent,Page Viewed,x,user-1');
    });

    test('writes only the header for an empty list', () {
      expect(hidden.toCsv([]), '#,recorded_at,kind,event\r\n');
    });
  });

  group('toMarkdown', () {
    test('writes a numbered heading and a property table for each record', () {
      final markdown = hidden.toMarkdown([
        _record(properties: {'screen': 'home'}),
        _record(id: 2, kind: 'people', name: r'$set', properties: {'company_name': 'Acme'}),
      ]);

      expect(
        markdown,
        '### 1. Item Viewed\n'
        '\n'
        '| Property | Value |\n'
        '|---|---|\n'
        '| screen | home |\n'
        '\n'
        '### 2. [people] \$set\n'
        '\n'
        '| Property | Value |\n'
        '|---|---|\n'
        '| company_name | Acme |\n',
      );
    });

    test('escapes pipes and turns line breaks into <br>', () {
      final markdown = hidden.recordToMarkdown(_record(properties: {'a|b': 'one|two\nthree'}));

      expect(markdown, contains(r'| a\|b | one\|two<br>three |'));
    });

    test('writes lists as one-line JSON', () {
      final markdown = hidden.recordToMarkdown(
        _record(
          properties: {
            'flags': ['a: true'],
          },
        ),
      );

      expect(markdown, contains('| flags | ["a: true"] |'));
    });

    test('says so when a record has no visible properties', () {
      final markdown = hidden.recordToMarkdown(_record());

      expect(markdown, '### Item Viewed\n\n_No properties._\n');
    });
  });
}
