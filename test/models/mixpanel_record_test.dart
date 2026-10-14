import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_devtools/src/models/mixpanel_record.dart';

void main() {
  group('MixpanelRecord.fromJson', () {
    test('parses every field of a track record', () {
      final record = MixpanelRecord.fromJson({
        'id': 7,
        'runId': 'run-1',
        'timestamp': 1791444276820,
        'kind': 'track',
        'name': 'Item Viewed',
        'properties': {'screen': 'home'},
        'superProperties': {
          'feature_flags': ['a: true'],
        },
        'distinctId': 'user-1',
        'groups': {'company': 'acme'},
      });

      expect(record.id, 7);
      expect(record.runId, 'run-1');
      expect(record.timestamp, DateTime.fromMillisecondsSinceEpoch(1791444276820));
      expect(record.kind, RecordKind.track);
      expect(record.name, 'Item Viewed');
      expect(record.properties, {'screen': 'home'});
      expect(record.superProperties, {
        'feature_flags': ['a: true'],
      });
      expect(record.distinctId, 'user-1');
      expect(record.groups, {'company': 'acme'});
      expect(record.isTrack, isTrue);
    });

    test('uses defaults when fields are missing or have the wrong type', () {
      final record = MixpanelRecord.fromJson({'id': 'seven', 'properties': 'not a map', 'superProperties': 3});

      expect(record.id, 0);
      expect(record.runId, '');
      expect(record.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
      expect(record.kind, RecordKind.unknown);
      expect(record.name, '');
      expect(record.properties, isEmpty);
      expect(record.superProperties, isNull);
      expect(record.distinctId, isNull);
      expect(record.groups, isNull);
    });

    test('converts non-string map keys to strings, also in nested maps', () {
      final record = MixpanelRecord.fromJson({
        'kind': 'track',
        'properties': {
          1: 'one',
          'nested': {2: 'two'},
        },
      });

      expect(record.properties, {
        '1': 'one',
        'nested': {'2': 'two'},
      });
    });

    test('keeps the wire name of an unknown kind for the label', () {
      final record = MixpanelRecord.fromJson({'kind': 'brand_new', 'name': 'thing'});

      expect(record.kind, RecordKind.unknown);
      expect(record.rawKind, 'brand_new');
      expect(record.label, '[brand_new] thing');
    });
  });

  group('MixpanelRecord labels and keys', () {
    test('a track record uses the event name as its label', () {
      final record = MixpanelRecord.fromJson({'kind': 'track', 'name': 'Button Clicked'});

      expect(record.label, 'Button Clicked');
    });

    test('other kinds show the wire kind in brackets', () {
      expect(MixpanelRecord.fromJson({'kind': 'people', 'name': r'$set'}).label, r'[people] $set');
      expect(MixpanelRecord.fromJson({'kind': 'super', 'name': 'register'}).label, '[super] register');
      expect(MixpanelRecord.fromJson({'kind': 'identity', 'name': 'identify'}).label, '[identity] identify');
    });

    test('maps every wire kind', () {
      const wire = {
        'track': RecordKind.track,
        'people': RecordKind.people,
        'group': RecordKind.group,
        'identity': RecordKind.identity,
        'super': RecordKind.superProperties,
        'timing': RecordKind.timing,
        'consent': RecordKind.consent,
        'flush': RecordKind.flush,
      };

      for (final entry in wire.entries) {
        expect(RecordKind.fromWire(entry.key), entry.value, reason: entry.key);
        expect(entry.value.wireName, entry.key);
      }
    });

    test('the key joins the run id and the id', () {
      final record = MixpanelRecord.fromJson({'runId': 'run-9', 'id': 3});

      expect(record.key, 'run-9:3');
    });
  });

  group('MixpanelRecord.toJson', () {
    test('writes the protocol JSON that fromJson reads back', () {
      final json = {
        'id': 7,
        'runId': 'run-1',
        'timestamp': 1791444276820,
        'kind': 'brand_new',
        'name': 'Item Viewed',
        'properties': {'screen': 'home'},
        'superProperties': {'tier': 'gold'},
        'distinctId': 'user-1',
        'groups': {'company': 'acme'},
      };

      final record = MixpanelRecord.fromJson(json);

      expect(record.toJson(), json);
      expect(MixpanelRecord.fromJson(record.toJson()).key, record.key);
    });

    test('leaves out the optional fields that are null', () {
      final record = MixpanelRecord.fromJson({'id': 1, 'runId': 'run', 'timestamp': 5, 'kind': 'track', 'name': 'A'});

      expect(record.toJson().keys, ['id', 'runId', 'timestamp', 'kind', 'name', 'properties']);
    });
  });
}
