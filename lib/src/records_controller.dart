import 'package:flutter/foundation.dart';

import 'models/mixpanel_record.dart';
import 'models/property_row.dart';

/// Holds the records that the tab shows, and the state of the toolbar.
class RecordsController extends ChangeNotifier {
  RecordsController({this.maxRecords = 5000});

  /// The tab drops the oldest records above this number.
  final int maxRecords;

  final List<MixpanelRecord> _records = [];
  final Set<String> _keys = {};
  final Map<String, String> _searchText = {};

  /// The numbers of the shown records, by key. Built on first use after each change.
  Map<String, int>? _numbers;

  MixpanelRecord? _selected;
  bool _recording = true;
  bool _showMixpanelProps = false;
  bool _showOtherCalls = true;
  String _query = '';

  List<MixpanelRecord> get records => List.unmodifiable(_records);

  /// The records of the shown kinds that match [query].
  List<MixpanelRecord> get visibleRecords {
    final query = _query.trim().toLowerCase();
    return [
      for (final record in _records)
        if (_isShown(record) && (query.isEmpty || _searchTextOf(record).contains(query))) record,
    ];
  }

  MixpanelRecord? get selected => _selected;

  /// When false, the tab drops incoming records.
  bool get recording => _recording;

  /// When false, the property table hides the Mixpanel system properties.
  bool get showMixpanelProps => _showMixpanelProps;

  /// When false, the list shows only `track` records. People, identity, super property, timing,
  /// consent, flush, and group calls are hidden.
  bool get showOtherCalls => _showOtherCalls;

  String get query => _query;

  /// The 1-based position of [record] among the records of the shown kinds. It does not change
  /// when the user searches. It is 0 for a record that is not shown.
  int numberOf(MixpanelRecord record) {
    final numbers = _numbers ??= {for (final (index, shown) in _records.where(_isShown).indexed) shown.key: index + 1};
    return numbers[record.key] ?? 0;
  }

  /// Adds one live record to the end of the list.
  void add(MixpanelRecord record) {
    if (!_recording || !_keys.add(record.key)) {
      return;
    }
    _records.add(record);
    _trim();
    notifyListeners();
  }

  /// Adds the records of a backlog that the list does not have, then sorts by time.
  void merge(Iterable<MixpanelRecord> backlog) {
    if (!_recording) {
      return;
    }
    final added = backlog.where((record) => _keys.add(record.key)).toList();
    if (added.isEmpty) {
      return;
    }
    _records
      ..addAll(added)
      ..sort(_byTimeThenId);
    _trim();
    notifyListeners();
  }

  /// Puts back the records and the toolbar state that were saved before a page reload. It
  /// ignores [recording], because saved records are not new records.
  void restore(Iterable<MixpanelRecord> saved, {bool? recording, bool? showMixpanelProps, bool? showOtherCalls}) {
    _records
      ..addAll(saved.where((record) => _keys.add(record.key)))
      ..sort(_byTimeThenId);
    _recording = recording ?? _recording;
    _showMixpanelProps = showMixpanelProps ?? _showMixpanelProps;
    _showOtherCalls = showOtherCalls ?? _showOtherCalls;
    _trim();
    notifyListeners();
  }

  void clear() {
    _records.clear();
    _keys.clear();
    _searchText.clear();
    _selected = null;
    notifyListeners();
  }

  void select(MixpanelRecord? record) {
    _selected = record;
    notifyListeners();
  }

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }

  void toggleRecording() {
    _recording = !_recording;
    notifyListeners();
  }

  void toggleMixpanelProps() {
    _showMixpanelProps = !_showMixpanelProps;
    notifyListeners();
  }

  void toggleOtherCalls() {
    _showOtherCalls = !_showOtherCalls;
    final selected = _selected;
    if (selected != null && !_isShown(selected)) {
      _selected = null;
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    _numbers = null;
    super.notifyListeners();
  }

  bool _isShown(MixpanelRecord record) => _showOtherCalls || record.isTrack;

  void _trim() {
    while (_records.length > maxRecords) {
      final removed = _records.removeAt(0);
      _keys.remove(removed.key);
      _searchText.remove(removed.key);
      if (identical(removed, _selected)) {
        _selected = null;
      }
    }
  }

  String _searchTextOf(MixpanelRecord record) {
    return _searchText.putIfAbsent(record.key, () {
      final rows = buildPropertyRows(record, showMixpanelProps: true);
      return [
        record.label,
        record.rawKind,
        for (final row in rows) ...[row.key, row.displayValue],
      ].join('\n').toLowerCase();
    });
  }

  static int _byTimeThenId(MixpanelRecord a, MixpanelRecord b) {
    final byTime = a.timestamp.compareTo(b.timestamp);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }
}
