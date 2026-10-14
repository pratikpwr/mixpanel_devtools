import 'package:flutter/foundation.dart';

import '../models/mixpanel_record.dart';

enum ConnectionStatus {
  /// DevTools has no running app.
  disconnected,

  /// The app runs, but it has not registered the recorder service extensions.
  notInstrumented,

  /// The app runs and has the recorder.
  ready,
}

/// The link between the tab and the recorder in the running app.
abstract class AppConnection {
  ValueListenable<ConnectionStatus> get status;

  /// Records as the app sends them.
  Stream<MixpanelRecord> get liveRecords;

  /// The buffer of the app. It arrives each time the recorder becomes available: when the tab
  /// connects, and after a hot restart.
  Stream<List<MixpanelRecord>> get backlogs;

  /// Empties the buffer in the app.
  Future<void> clear();

  /// Asks the app to send its queued events to Mixpanel now.
  Future<void> flush();

  void dispose();
}
