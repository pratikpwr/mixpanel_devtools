import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_devtools/src/models/mixpanel_record.dart';
import 'package:mixpanel_devtools/src/persistence/key_value_store.dart';
import 'package:mixpanel_devtools/src/persistence/records_persistence.dart';
import 'package:mixpanel_devtools/src/records_controller.dart';

MixpanelRecord _record(int id, {String runId = 'run-1'}) {
  return MixpanelRecord.fromJson({
    'id': id,
    'runId': runId,
    'timestamp': 1000 + id,
    'kind': 'track',
    'name': 'Event $id',
  });
}

List<String> _keys(Iterable<MixpanelRecord> records) => records.map((record) => record.key).toList();

void main() {
  late MemoryKeyValueStore store;
  late MemoryKeyValueStore preferences;
  late RecordsController controller;
  late RecordsPersistence persistence;

  setUp(() {
    store = MemoryKeyValueStore();
    preferences = MemoryKeyValueStore();
    controller = RecordsController();
    persistence = RecordsPersistence(store: store, preferences: preferences, controller: controller, maxSaved: 3);
  });

  tearDown(() {
    persistence.dispose();
    controller.dispose();
  });

  RecordsPersistence reloaded() {
    final next = RecordsController();
    addTearDown(next.dispose);
    final nextPersistence = RecordsPersistence(store: store, preferences: preferences, controller: next, maxSaved: 3);
    addTearDown(nextPersistence.dispose);
    return nextPersistence;
  }

  test('records and the recording state survive a page reload for the same app', () {
    persistence.attach('ws://app-1');
    controller.add(_record(1));
    controller.add(_record(2));
    controller.toggleRecording();

    final next = reloaded()..attach('ws://app-1');

    expect(_keys(next.controller.records), ['run-1:1', 'run-1:2']);
    expect(next.controller.recording, isFalse);
  });

  test('the display modes come back at once, also for another app', () {
    controller
      ..toggleMixpanelProps()
      ..toggleOtherCalls();

    final next = reloaded();

    expect(next.controller.showMixpanelProps, isTrue);
    expect(next.controller.showOtherCalls, isFalse);

    next.attach('ws://app-2');

    expect(next.controller.showMixpanelProps, isTrue);
    expect(next.controller.showOtherCalls, isFalse);
  });

  test('the recording state does not carry over to another app', () {
    persistence.attach('ws://app-1');
    controller.toggleRecording();

    final next = reloaded()..attach('ws://app-2');

    expect(next.controller.recording, isTrue);
  });

  test('another app does not see the records', () {
    persistence.attach('ws://app-1');
    controller.add(_record(1));

    final next = reloaded()..attach('ws://app-2');

    expect(next.controller.records, isEmpty);
  });

  test('Clear also clears the saved records', () {
    persistence.attach('ws://app-1');
    controller.add(_record(1));
    controller.clear();

    final next = reloaded()..attach('ws://app-1');

    expect(next.controller.records, isEmpty);
  });

  test('saves only the most recent records', () {
    persistence.attach('ws://app-1');
    for (var id = 1; id <= 5; id++) {
      controller.add(_record(id));
    }

    final next = reloaded()..attach('ws://app-1');

    expect(_keys(next.controller.records), ['run-1:3', 'run-1:4', 'run-1:5']);
  });

  test('records that arrive before attach are kept and saved', () {
    controller.add(_record(1));

    persistence.attach('ws://app-1');
    final next = reloaded()..attach('ws://app-1');

    expect(_keys(next.controller.records), ['run-1:1']);
  });

  test('a second attach with the same key changes nothing', () {
    persistence.attach('ws://app-1');
    controller.add(_record(1));

    persistence.attach('ws://app-1');

    expect(controller.records, hasLength(1));
  });

  test('corrupt saved data is ignored', () {
    store.write(RecordsPersistence.storageKey('ws://app-1'), 'not json');

    persistence.attach('ws://app-1');

    expect(controller.records, isEmpty);
  });

  test('a store that throws on write does not break the tab', () {
    final failing = RecordsPersistence(store: _FailingStore(), preferences: _FailingStore(), controller: controller);
    addTearDown(failing.dispose);
    failing.attach('ws://app-1');

    controller
      ..add(_record(1))
      ..toggleOtherCalls();

    expect(controller.records, hasLength(1));
  });

  test('the saved value is protocol JSON', () {
    persistence.attach('ws://app-1');
    controller.add(_record(1));

    final saved = jsonDecode(store.read(RecordsPersistence.storageKey('ws://app-1'))!) as Map<String, Object?>;

    expect((saved['records'] as List).single, _record(1).toJson());
  });
}

class _FailingStore implements KeyValueStore {
  @override
  String? read(String key) => null;

  @override
  void write(String key, String value) => throw StateError('quota exceeded');
}
