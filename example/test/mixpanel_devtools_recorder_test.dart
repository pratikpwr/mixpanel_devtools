import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_devtools_example/mixpanel_devtools_recorder.dart';
import 'package:mixpanel_flutter/codec/mixpanel_message_codec.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

const _channel = MethodChannel('mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));

class _Opaque {
  @override
  String toString() => 'opaque';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> channelCalls;
  late List<(String, Map<String, Object?>)> posted;
  late Map<String, Object?> seededSuperProperties;
  late String deviceDistinctId;
  late MixpanelDevtoolsRecorder recorder;
  late RecordingMixpanel mixpanel;

  setUp(() async {
    channelCalls = [];
    posted = [];
    seededSuperProperties = {};
    deviceDistinctId = 'device-id';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      channelCalls.add(call);
      return switch (call.method) {
        'getSuperProperties' => seededSuperProperties,
        'getDistinctId' => deviceDistinctId,
        _ => null,
      };
    });
    recorder = MixpanelDevtoolsRecorder(
      runId: 'run-1',
      now: () => DateTime.fromMillisecondsSinceEpoch(1791444276820),
      postEvent: (kind, data) => posted.add((kind, data)),
    );
    mixpanel = RecordingMixpanel('token', recorder);
    await pumpEventQueue();
    channelCalls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  List<String> methods() => channelCalls.map((call) => call.method).toList();

  test('instrument wraps the instance outside release builds', () {
    final instrumented = MixpanelDevtoolsRecorder.instrument(Mixpanel('token'), token: 'token');

    expect(instrumented, isA<RecordingMixpanel>());
  });

  test('track records the call, posts it, then forwards it to the plugin', () async {
    await mixpanel.track('Item Viewed', properties: {'screen': 'home'});

    expect(recorder.records.single, {
      'id': 1,
      'runId': 'run-1',
      'timestamp': 1791444276820,
      'kind': 'track',
      'name': 'Item Viewed',
      'properties': {'screen': 'home'},
      'superProperties': <String, Object?>{},
      'distinctId': 'device-id',
    });
    expect(posted.single.$1, 'mixpanel_devtools:record');
    expect(posted.single.$2, recorder.records.single);
    expect(methods(), ['track']);
    expect(channelCalls.single.arguments, {
      'eventName': 'Item Viewed',
      'properties': {'screen': 'home'},
    });
  });

  test('trackWithGroups records the groups', () async {
    await mixpanel.trackWithGroups('Joined', {'plan': 'pro'}, {'company': 'acme'});

    expect(recorder.records.single['groups'], {'company': 'acme'});
    expect(methods(), ['trackWithGroups']);
  });

  test('records keep the call order and increasing ids', () async {
    final first = mixpanel.track('A');
    final second = mixpanel.identify('user-1');
    final third = mixpanel.track('B');
    await Future.wait([first, second, third]);

    expect(recorder.records.map((record) => record['name']), ['A', 'identify', 'B']);
    expect(recorder.records.map((record) => record['id']), [1, 2, 3]);
  });

  group('super properties', () {
    test('the seed from the plugin is in the snapshot', () async {
      seededSuperProperties = {'app': 'demo'};
      final seeded = RecordingMixpanel('token', recorder);
      await pumpEventQueue();

      await seeded.track('Item Viewed');

      expect(recorder.records.last['superProperties'], {'app': 'demo'});
    });

    test('a register before the seed arrives wins over the seed', () async {
      seededSuperProperties = {'tier': 'seed'};
      final seeded = RecordingMixpanel('token', recorder);
      await seeded.registerSuperProperties({'tier': 'registered'});
      await pumpEventQueue();

      await seeded.track('Item Viewed');

      expect(recorder.records.last['superProperties'], {'tier': 'registered'});
    });

    test('register, register once, unregister, and clear update the snapshot', () async {
      await mixpanel.registerSuperProperties({'tier': 'gold', 'plan': 'pro'});
      await mixpanel.registerSuperPropertiesOnce({'tier': 'silver', 'region': 'eu'});
      await mixpanel.track('After register');
      await mixpanel.unregisterSuperProperty('plan');
      await mixpanel.track('After unregister');
      await mixpanel.clearSuperProperties();
      await mixpanel.track('After clear');

      Map<String, Object?>? supersOf(String name) {
        return recorder.records.singleWhere((record) => record['name'] == name)['superProperties']
            as Map<String, Object?>?;
      }

      expect(supersOf('After register'), {'tier': 'gold', 'plan': 'pro', 'region': 'eu'});
      expect(supersOf('After unregister'), {'tier': 'gold', 'region': 'eu'});
      expect(supersOf('After clear'), isEmpty);
      expect(recorder.records.where((record) => record['kind'] == 'super').map((record) => record['name']), [
        'register',
        'register_once',
        'unregister',
        'clear',
      ]);
      expect(methods(), containsAllInOrder(['registerSuperProperties', 'registerSuperPropertiesOnce']));
    });

    test('only track records carry the snapshot', () async {
      await mixpanel.registerSuperProperties({'tier': 'gold'});

      expect(recorder.records.single.containsKey('superProperties'), isFalse);
    });
  });

  group('identity', () {
    test('identify sets the distinct id of later records', () async {
      await mixpanel.identify('user-1');
      await mixpanel.track('Item Viewed');

      expect(recorder.records.first['properties'], {'distinct_id': 'user-1'});
      expect(recorder.records.last['distinctId'], 'user-1');
    });

    test('alias records both ids and forwards', () async {
      mixpanel.alias('user-1', 'device-id');
      await pumpEventQueue();

      expect(recorder.records.single['properties'], {'alias': 'user-1', 'distinct_id': 'device-id'});
      expect(methods(), ['alias']);
    });

    test('reset clears the super properties and reads the new distinct id', () async {
      await mixpanel.registerSuperProperties({'tier': 'gold'});
      await mixpanel.identify('user-1');
      deviceDistinctId = 'new-device-id';

      await mixpanel.reset();
      await mixpanel.track('After reset');

      expect(recorder.records.last['superProperties'], isEmpty);
      expect(recorder.records.last['distinctId'], 'new-device-id');
    });
  });

  test('timeEvent, consent, flush, and groups are recorded', () async {
    mixpanel.timeEvent('Page Viewed');
    mixpanel.optOutTracking();
    mixpanel.optInTracking();
    await mixpanel.flush();
    mixpanel.setGroup('company', 'acme');
    await pumpEventQueue();

    expect(recorder.records.map((record) => '${record['kind']}:${record['name']}'), [
      'timing:timeEvent',
      'consent:optOutTracking',
      'consent:optInTracking',
      'flush:flush',
      'group:setGroup',
    ]);
    expect(recorder.records.first['properties'], {'event': 'Page Viewed'});
    expect(methods(), ['timeEvent', 'optOutTracking', 'optInTracking', 'flush', 'setGroup']);
  });

  test('people calls are recorded with their Mixpanel operation names', () async {
    final people = mixpanel.getPeople();
    people.set('company_name', 'Acme');
    people.setOnce('first_seen', 'today');
    people.increment('sessions', 1);
    people.append('tags', 'a');
    people.union('tags', ['b']);
    people.remove('tags', 'a');
    people.unset('tags');
    people.deleteUser();
    await pumpEventQueue();

    expect(identical(people, mixpanel.getPeople()), isTrue);
    expect(recorder.records.map((record) => record['name']), [
      r'$set',
      r'$set_once',
      r'$add',
      r'$append',
      r'$union',
      r'$remove',
      r'$unset',
      r'$delete',
    ]);
    expect(recorder.records.first['properties'], {'company_name': 'Acme'});
    expect(recorder.records.every((record) => record['kind'] == 'people'), isTrue);
    expect(methods(), ['set', 'setOnce', 'increment', 'append', 'union', 'remove', 'unset', 'deleteUser']);
  });

  test('values that JSON cannot encode become JSON-safe', () async {
    await mixpanel.track(
      'Odd values',
      properties: {
        'when': DateTime.utc(2026, 10, 8, 9),
        'link': Uri.parse('https://example.com/a'),
        'by_id': {1: 'one'},
        'not_a_number': double.nan,
        'list': [DateTime.utc(2026)],
      },
    );

    final record = recorder.records.single;
    expect(() => jsonEncode(record), returnsNormally);
    expect(record['properties'], {
      'when': '2026-10-08T09:00:00.000Z',
      'link': 'https://example.com/a',
      'by_id': {'1': 'one'},
      'not_a_number': 'NaN',
      'list': ['2026-01-01T00:00:00.000Z'],
    });
  });

  test('a value that only toString can show is still recorded', () {
    recorder.record(
      'track',
      'Custom object',
      properties: {
        'object': _Opaque(),
        'list': [_Opaque()],
      },
    );

    expect(() => jsonEncode(recorder.records.single), returnsNormally);
    expect(recorder.records.single['properties'], {
      'object': 'opaque',
      'list': ['opaque'],
    });
  });

  test('the buffer keeps the most recent records', () {
    for (var i = 0; i < MixpanelDevtoolsRecorder.maxRecords + 5; i++) {
      recorder.record('track', 'Event $i');
    }

    expect(recorder.records, hasLength(MixpanelDevtoolsRecorder.maxRecords));
    expect(recorder.records.first['id'], 6);
  });

  group('service extensions', () {
    test('getRecords returns the protocol version and the buffer', () async {
      await mixpanel.track('Item Viewed');

      final response = await recorder.handleServiceExtension(MixpanelDevtoolsRecorder.getRecordsMethod);

      expect(jsonDecode(response.result!), {'version': 1, 'records': recorder.records});
    });

    test('clear empties the buffer', () async {
      await mixpanel.track('Item Viewed');

      await recorder.handleServiceExtension(MixpanelDevtoolsRecorder.clearMethod);

      expect(recorder.records, isEmpty);
    });

    test('flush forwards a flush to the plugin', () async {
      await recorder.handleServiceExtension(MixpanelDevtoolsRecorder.flushMethod);

      expect(methods(), ['flush']);
    });

    test('an unknown method returns an error', () async {
      final response = await recorder.handleServiceExtension('ext.mixpanel_devtools.unknown');

      expect(response.result, isNull);
      expect(response.errorCode, isNotNull);
    });
  });
}
