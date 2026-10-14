/// Names shared by the app-side recorder and this DevTools extension.
///
/// See `doc/specs/2026-10-08-mixpanel-devtools-design.md` for the full protocol.
abstract final class MixpanelDevtoolsProtocol {
  /// The protocol version that this extension reads.
  static const int version = 1;

  /// The `Extension` stream event kind for one recorded Mixpanel call.
  static const String recordEventKind = 'mixpanel_devtools:record';

  /// Returns `{"version": 1, "records": [...]}`.
  static const String getRecordsMethod = 'ext.mixpanel_devtools.getRecords';

  /// Empties the buffer in the app.
  static const String clearMethod = 'ext.mixpanel_devtools.clear';

  /// Calls `Mixpanel.flush()` in the app.
  static const String flushMethod = 'ext.mixpanel_devtools.flush';
}
