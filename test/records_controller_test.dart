import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_devtools/src/models/mixpanel_record.dart';
import 'package:mixpanel_devtools/src/records_controller.dart';

MixpanelRecord _record(
  int id, {
  String runId = 'run-1',
  int? timestamp,
  String kind = 'track',
  String? name,
  Map<String, Object?> properties = const {},
  Map<String, Object?>? superProperties,
}) {
  return MixpanelRecord.fromJson({
    'id': id,
    'runId': runId,
    'timestamp': timestamp ?? 1000 + id,
    'kind': kind,
    'name': name ?? 'Event $id',
    'properties': properties,
    if (superProperties != null) 'superProperties': superProperties,
  });
}

List<String> _keys(Iterable<MixpanelRecord> records) => records.map((record) => record.key).toList();

void main() {
  late RecordsController controller;
  late int notifications;

  setUp(() {
    controller = RecordsController();
    notifications = 0;
    controller.addListener(() => notifications++);
  });

  tearDown(() => controller.dispose());

  test('starts empty, recording, and with mixpanel props hidden', () {
    expect(controller.records, isEmpty);
    expect(controller.selected, isNull);
    expect(controller.recording, isTrue);
    expect(controller.showMixpanelProps, isFalse);
    expect(controller.showOtherCalls, isTrue);
    expect(controller.query, '');
  });

  group('add', () {
    test('appends records in arrival order and notifies', () {
      controller.add(_record(1));
      controller.add(_record(2));

      expect(_keys(controller.records), ['run-1:1', 'run-1:2']);
      expect(notifications, 2);
    });

    test('drops a record whose key is already in the list', () {
      controller.add(_record(1));
      controller.add(_record(1));

      expect(controller.records, hasLength(1));
      expect(notifications, 1);
    });

    test('drops records while paused', () {
      controller.toggleRecording();
      controller.add(_record(1));

      expect(controller.recording, isFalse);
      expect(controller.records, isEmpty);
    });

    test('drops the oldest records above the limit', () {
      final small = RecordsController(maxRecords: 2);
      small.add(_record(1));
      small.add(_record(2));
      small.add(_record(3));

      expect(_keys(small.records), ['run-1:2', 'run-1:3']);
      small.dispose();
    });
  });

  group('merge', () {
    test('adds the missing records of a backlog and keeps time order', () {
      controller.add(_record(3));
      controller.merge([_record(1), _record(2), _record(3)]);

      expect(_keys(controller.records), ['run-1:1', 'run-1:2', 'run-1:3']);
      expect(notifications, 2);
    });

    test('keeps the records of an earlier run after a hot restart', () {
      controller.merge([_record(1, runId: 'old', timestamp: 10), _record(2, runId: 'old', timestamp: 20)]);
      controller.merge([_record(1, runId: 'new', timestamp: 30)]);

      expect(_keys(controller.records), ['old:1', 'old:2', 'new:1']);
    });

    test('orders equal timestamps by id', () {
      controller.merge([_record(2, timestamp: 5), _record(1, timestamp: 5)]);

      expect(_keys(controller.records), ['run-1:1', 'run-1:2']);
    });

    test('does not notify when nothing is new', () {
      controller.add(_record(1));
      notifications = 0;

      controller.merge([_record(1)]);

      expect(notifications, 0);
    });

    test('drops the backlog while paused', () {
      controller.toggleRecording();
      controller.merge([_record(1)]);

      expect(controller.records, isEmpty);
    });
  });

  group('selection', () {
    test('select stores the record and survives new records', () {
      final first = _record(1);
      controller.add(first);
      controller.select(first);
      controller.add(_record(2));

      expect(controller.selected, same(first));
    });

    test('clear empties the list and the selection', () {
      final first = _record(1);
      controller.add(first);
      controller.select(first);

      controller.clear();

      expect(controller.records, isEmpty);
      expect(controller.selected, isNull);
    });

    test('numberOf gives the 1-based position in the full list', () {
      final second = _record(2);
      controller.add(_record(1));
      controller.add(second);
      controller.setQuery('event 2');

      expect(controller.numberOf(second), 2);
    });
  });

  group('search', () {
    setUp(() {
      controller.add(_record(1, name: 'Item Viewed', properties: {'screen': 'Home'}));
      controller.add(_record(2, name: 'Button Clicked', properties: {'button_type': 'checkout'}));
      controller.add(_record(3, kind: 'people', name: r'$set', properties: {'company_name': 'Acme'}));
      controller.add(_record(4, name: 'Page Viewed', superProperties: {'tier': 'Gold'}));
    });

    List<String> visibleNames() => controller.visibleRecords.map((record) => record.name).toList();

    test('shows everything for an empty query', () {
      expect(controller.visibleRecords, hasLength(4));
    });

    test('matches the event name without case', () {
      controller.setQuery('viewed');

      expect(visibleNames(), ['Item Viewed', 'Page Viewed']);
    });

    test('matches the kind', () {
      controller.setQuery('people');

      expect(visibleNames(), [r'$set']);
    });

    test('matches property keys and values', () {
      controller.setQuery('button_type');
      expect(visibleNames(), ['Button Clicked']);

      controller.setQuery('home');
      expect(visibleNames(), ['Item Viewed']);
    });

    test('matches super property values', () {
      controller.setQuery('gold');

      expect(visibleNames(), ['Page Viewed']);
    });

    test('ignores spaces around the query', () {
      controller.setQuery('  acme ');

      expect(visibleNames(), [r'$set']);
    });
  });

  test('toggleMixpanelProps flips the mode and notifies', () {
    controller.toggleMixpanelProps();

    expect(controller.showMixpanelProps, isTrue);
    expect(notifications, 1);
  });

  group('restore', () {
    test('adds saved records in time order, also while paused', () {
      controller.toggleRecording();

      controller.restore([_record(2), _record(1)]);

      expect(_keys(controller.records), ['run-1:1', 'run-1:2']);
    });

    test('sets the saved toolbar state', () {
      controller.restore(const [], recording: false, showMixpanelProps: true);

      expect(controller.recording, isFalse);
      expect(controller.showMixpanelProps, isTrue);
    });

    test('drops records that the list already has', () {
      controller.add(_record(1));

      controller.restore([_record(1), _record(2)]);

      expect(controller.records, hasLength(2));
    });
  });

  group('other calls', () {
    late MixpanelRecord firstTrack;
    late MixpanelRecord superCall;
    late MixpanelRecord secondTrack;

    setUp(() {
      firstTrack = _record(1, name: 'Item Viewed');
      superCall = _record(2, kind: 'super', name: 'register', properties: {'tier': 'gold'});
      secondTrack = _record(3, name: 'Button Clicked');
      controller
        ..add(firstTrack)
        ..add(superCall)
        ..add(secondTrack);
      notifications = 0;
    });

    test('hiding them leaves only track records visible, and keeps all records', () {
      controller.toggleOtherCalls();

      expect(controller.showOtherCalls, isFalse);
      expect(controller.visibleRecords, [firstTrack, secondTrack]);
      expect(controller.records, hasLength(3));
      expect(notifications, 1);
    });

    test('numbers count only the shown records, so they stay in sequence', () {
      expect(controller.numberOf(secondTrack), 3);

      controller.toggleOtherCalls();

      expect(controller.numberOf(firstTrack), 1);
      expect(controller.numberOf(secondTrack), 2);
    });

    test('numbers do not change when the user searches', () {
      controller
        ..toggleOtherCalls()
        ..setQuery('button');

      expect(controller.visibleRecords, [secondTrack]);
      expect(controller.numberOf(secondTrack), 2);
    });

    test('a search does not bring hidden calls back', () {
      controller
        ..toggleOtherCalls()
        ..setQuery('gold');

      expect(controller.visibleRecords, isEmpty);
    });

    test('hiding them unselects a selected call that is no longer shown', () {
      controller
        ..select(superCall)
        ..toggleOtherCalls();

      expect(controller.selected, isNull);
    });

    test('hiding them keeps a selected track record', () {
      controller
        ..select(secondTrack)
        ..toggleOtherCalls();

      expect(controller.selected, same(secondTrack));
    });

    test('new records get numbers in sequence while calls are hidden', () {
      controller.toggleOtherCalls();
      final third = _record(5, name: 'Page Viewed');
      controller
        ..add(_record(4, kind: 'people', name: r'$set'))
        ..add(third);

      expect(controller.numberOf(third), 3);
    });

    test('restore sets the saved mode', () {
      controller.restore(const [], showOtherCalls: false);

      expect(controller.showOtherCalls, isFalse);
    });
  });
}
