import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_devtools/src/connection/app_connection.dart';
import 'package:mixpanel_devtools/src/models/mixpanel_record.dart';
import 'package:mixpanel_devtools/src/records_controller.dart';
import 'package:mixpanel_devtools/src/ui/mixpanel_screen.dart';

class _FakeConnection implements AppConnection {
  final statusNotifier = ValueNotifier(ConnectionStatus.ready);
  final live = StreamController<MixpanelRecord>.broadcast();
  final backlog = StreamController<List<MixpanelRecord>>.broadcast();
  int clearCalls = 0;
  int flushCalls = 0;

  @override
  ValueListenable<ConnectionStatus> get status => statusNotifier;

  @override
  Stream<MixpanelRecord> get liveRecords => live.stream;

  @override
  Stream<List<MixpanelRecord>> get backlogs => backlog.stream;

  @override
  Future<void> clear() async => clearCalls++;

  @override
  Future<void> flush() async => flushCalls++;

  @override
  void dispose() {}
}

MixpanelRecord _record(
  int id, {
  String kind = 'track',
  String? name,
  Map<String, Object?> properties = const {},
  Map<String, Object?>? superProperties,
}) {
  return MixpanelRecord.fromJson({
    'id': id,
    'runId': 'run',
    'timestamp': 1791444276820 + id,
    'kind': kind,
    'name': name ?? 'Event $id',
    'properties': properties,
    if (superProperties != null) 'superProperties': superProperties,
    'distinctId': 'user-1',
  });
}

void main() {
  late _FakeConnection connection;
  late RecordsController controller;
  late List<(String, String)> copies;
  late List<(String, String, String)> downloads;

  setUp(() {
    connection = _FakeConnection();
    controller = RecordsController();
    copies = [];
    downloads = [];
  });

  tearDown(() => controller.dispose());

  Future<void> pumpScreen(WidgetTester tester, {Size size = const Size(1400, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MixpanelScreen(
            controller: controller,
            connection: connection,
            copyToClipboard: (text, message) => copies.add((text, message)),
            download: (name, content, mime) => downloads.add((name, content, mime)),
            now: () => DateTime(2026, 10, 8, 9, 5, 7),
          ),
        ),
      ),
    );
  }

  Future<void> sendLive(WidgetTester tester, MixpanelRecord record) async {
    connection.live.add(record);
    await tester.pump();
  }

  group('empty states', () {
    testWidgets('asks for a running app when disconnected', (tester) async {
      connection.statusNotifier.value = ConnectionStatus.disconnected;
      await pumpScreen(tester);

      expect(find.textContaining('Waiting for a running app'), findsOneWidget);
      expect(find.text('No app'), findsOneWidget);
    });

    testWidgets('shows the setup help when the app has no recorder', (tester) async {
      connection.statusNotifier.value = ConnectionStatus.notInstrumented;
      await pumpScreen(tester);

      expect(find.textContaining('does not send Mixpanel records'), findsOneWidget);
      expect(find.textContaining('MixpanelDevtoolsRecorder.instrument'), findsOneWidget);
    });

    testWidgets('says that no events arrived yet when the recorder is connected', (tester) async {
      await pumpScreen(tester);

      expect(find.textContaining('No events yet'), findsOneWidget);
      expect(find.text('Recorder connected'), findsOneWidget);
    });
  });

  group('records', () {
    testWidgets('lists live records with their number and label', (tester) async {
      await pumpScreen(tester);

      await sendLive(tester, _record(1, name: 'Item Viewed'));
      await sendLive(tester, _record(2, kind: 'people', name: r'$set'));

      expect(find.text('Events (2)'), findsOneWidget);
      expect(find.text('Item Viewed'), findsOneWidget);
      expect(find.text(r'[people] $set'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
    });

    testWidgets('shows a backlog in time order', (tester) async {
      await pumpScreen(tester);

      connection.backlog.add([_record(2, name: 'Second'), _record(1, name: 'First')]);
      await tester.pump();

      final first = tester.getTopLeft(find.text('First'));
      final second = tester.getTopLeft(find.text('Second'));
      expect(first.dy, lessThan(second.dy));
    });

    testWidgets('keeps the list after the app disconnects', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, name: 'Item Viewed'));

      connection.statusNotifier.value = ConnectionStatus.disconnected;
      await tester.pump();

      expect(find.text('Item Viewed'), findsOneWidget);
    });

    testWidgets('drops live records while paused', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, name: 'Before pause'));

      await tester.tap(find.text('Recording'));
      await tester.pump();
      await sendLive(tester, _record(2, name: 'During pause'));

      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Before pause'), findsOneWidget);
      expect(find.text('During pause'), findsNothing);
    });
  });

  group('properties', () {
    testWidgets('shows the property table of the tapped record', (tester) async {
      await pumpScreen(tester);
      await sendLive(
        tester,
        _record(1, name: 'Item Viewed', properties: {'screen': 'home'}, superProperties: {'tier': 'gold'}),
      );

      expect(find.text('Select an event to see its properties.'), findsOneWidget);

      await tester.tap(find.text('Item Viewed'));
      await tester.pump();

      expect(find.text('screen'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);
      expect(find.text('tier'), findsOneWidget);
      expect(find.text('super'), findsOneWidget);
      expect(find.text('time'), findsNothing);
    });

    testWidgets('the Mixpanel props toggle shows time and distinct_id', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, name: 'Item Viewed'));
      await tester.tap(find.text('Item Viewed'));
      await tester.pump();

      await tester.tap(find.text('Mixpanel props: Hidden'));
      await tester.pump();

      expect(find.text('Mixpanel props: Shown'), findsOneWidget);
      expect(find.text('time'), findsOneWidget);
      expect(find.text('distinct_id'), findsOneWidget);
      expect(find.text('user-1'), findsOneWidget);
    });

    testWidgets('a long list value wraps without overflow', (tester) async {
      await pumpScreen(tester, size: const Size(1000, 700));
      await sendLive(
        tester,
        _record(
          1,
          name: 'Item Viewed',
          superProperties: {
            'feature_flags': [for (var i = 0; i < 60; i++) 'a_very_long_feature_flag_name_number_$i: true'],
          },
        ),
      );

      await tester.tap(find.text('Item Viewed'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('feature_flags'), findsOneWidget);
    });

    testWidgets('copies the selected record as JSON and as Markdown', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, name: 'Button Clicked', properties: {'button': 'checkout'}));
      await tester.tap(find.text('Button Clicked'));
      await tester.pump();

      await tester.tap(find.text('Copy JSON'));
      await tester.tap(find.text('Copy Markdown'));

      expect(jsonDecode(copies[0].$1), containsPair('properties', {'button': 'checkout'}));
      expect(copies[0].$2, 'Copied "Button Clicked" as JSON');
      expect(copies[1].$1, startsWith('### 1. Button Clicked'));
      expect(copies[1].$1, contains('| button | checkout |'));
    });
  });

  group('toolbar', () {
    testWidgets('search filters the list and shows the count', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, name: 'Item Viewed'));
      await sendLive(tester, _record(2, name: 'Button Clicked'));

      await tester.enterText(find.byType(TextField), 'button');
      await tester.pump();

      expect(find.text('Events (1 of 2)'), findsOneWidget);
      expect(find.text('Button Clicked'), findsOneWidget);
      expect(find.text('Item Viewed'), findsNothing);
    });

    testWidgets('Other calls hides non-track rows and keeps the numbers in sequence', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, kind: 'super', name: 'register'));
      await sendLive(tester, _record(2, kind: 'identity', name: 'identify'));
      await sendLive(tester, _record(3, name: 'Item Viewed'));
      await sendLive(tester, _record(4, kind: 'people', name: r'$set'));
      await sendLive(tester, _record(5, name: 'Button Clicked'));

      await tester.tap(find.text('Other calls: Shown'));
      await tester.pump();

      expect(find.text('Other calls: Hidden'), findsOneWidget);
      expect(find.text('Events (2 of 5)'), findsOneWidget);
      expect(find.text('[super] register'), findsNothing);
      expect(find.text('[identity] identify'), findsNothing);
      expect(find.text(r'[people] $set'), findsNothing);
      expect(find.text('Item Viewed'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsNothing);
    });

    testWidgets('Export leaves out the hidden calls', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, kind: 'super', name: 'register'));
      await sendLive(tester, _record(2, name: 'Item Viewed'));
      await tester.tap(find.text('Other calls: Shown'));
      await tester.pump();

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy all as Markdown'));
      await tester.pumpAndSettle();

      expect(copies.single.$1, startsWith('### 1. Item Viewed'));
      expect(copies.single.$1, isNot(contains('register')));
    });

    testWidgets('Clear empties the list and the app buffer', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, name: 'Item Viewed'));

      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(connection.clearCalls, 1);
      expect(find.text('Item Viewed'), findsNothing);
      expect(find.textContaining('No events yet'), findsOneWidget);
    });

    testWidgets('Flush asks the app to flush', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Flush'));
      await tester.pump();

      expect(connection.flushCalls, 1);
    });

    testWidgets('Flush is disabled without a recorder', (tester) async {
      connection.statusNotifier.value = ConnectionStatus.notInstrumented;
      await pumpScreen(tester);

      await tester.tap(find.text('Flush'));
      await tester.pump();

      expect(connection.flushCalls, 0);
    });

    testWidgets('Export downloads the visible records as JSON, CSV, and Markdown', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, name: 'Item Viewed', properties: {'screen': 'home'}));

      for (final label in ['Download JSON', 'Download CSV', 'Download Markdown']) {
        await tester.tap(find.text('Export'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(downloads.map((download) => download.$1), [
        'mixpanel_events_20261008_090507.json',
        'mixpanel_events_20261008_090507.csv',
        'mixpanel_events_20261008_090507.md',
      ]);
      expect(downloads.map((download) => download.$3), ['application/json', 'text/csv', 'text/markdown']);
      expect(downloads[1].$2, startsWith('#,recorded_at,kind,event,screen\r\n'));
    });

    testWidgets('Export can copy all visible records as Markdown', (tester) async {
      await pumpScreen(tester);
      await sendLive(tester, _record(1, name: 'Item Viewed'));
      await sendLive(tester, _record(2, name: 'Button Clicked'));

      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy all as Markdown'));
      await tester.pumpAndSettle();

      expect(copies.single.$1, contains('### 2. Button Clicked'));
      expect(copies.single.$2, 'Copied 2 events as Markdown');
    });
  });
}
