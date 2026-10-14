import 'dart:convert';

import '../models/mixpanel_record.dart';
import '../models/property_row.dart';

/// Turns records into text that other teams can read: JSON, CSV, or Markdown.
///
/// Each export uses the same rows as the property table, so [showMixpanelProps] has the
/// same effect as the toggle in the tab.
class RecordExporter {
  RecordExporter({required this.showMixpanelProps});

  final bool showMixpanelProps;

  static const _prettyJson = JsonEncoder.withIndent('  ', _toEncodable);
  static const _compactJson = JsonEncoder(_toEncodable);

  String toJson(List<MixpanelRecord> records) => _prettyJson.convert(records.map(_toJsonObject).toList());

  String recordToJson(MixpanelRecord record) => _prettyJson.convert(_toJsonObject(record));

  /// One row per record. The columns after `event` are the union of all property keys, in
  /// first-seen order. A property key that is the same as a fixed column name gets the header
  /// `property: <key>`.
  String toCsv(List<MixpanelRecord> records) {
    final rowsByRecord = [for (final record in records) _rows(record)];
    final keys = <String>{
      for (final rows in rowsByRecord)
        for (final row in rows) row.key,
    };

    final buffer =
        StringBuffer()..write(
          _csvLine([
            ..._csvFixedColumns,
            for (final key in keys) _csvFixedColumns.contains(key) ? 'property: $key' : key,
          ]),
        );
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final values = {for (final row in rowsByRecord[i]) row.key: _flatValue(row.value)};
      buffer.write(
        _csvLine([
          '${i + 1}',
          _isoTime(record),
          record.rawKind,
          record.name,
          for (final key in keys) values[key] ?? '',
        ]),
      );
    }
    return buffer.toString();
  }

  String toMarkdown(List<MixpanelRecord> records) {
    return [for (var i = 0; i < records.length; i++) recordToMarkdown(records[i], index: i + 1)].join('\n');
  }

  String recordToMarkdown(MixpanelRecord record, {int? index}) {
    final title = index == null ? record.label : '$index. ${record.label}';
    final buffer = StringBuffer('### ${_markdownCell(title)}\n\n');
    final rows = _rows(record);
    if (rows.isEmpty) {
      buffer.write('_No properties._\n');
      return buffer.toString();
    }
    buffer.write('| Property | Value |\n|---|---|\n');
    for (final row in rows) {
      buffer.write('| ${_markdownCell(row.key)} | ${_markdownCell(_flatValue(row.value))} |\n');
    }
    return buffer.toString();
  }

  List<PropertyRow> _rows(MixpanelRecord record) => buildPropertyRows(record, showMixpanelProps: showMixpanelProps);

  Map<String, Object?> _toJsonObject(MixpanelRecord record) {
    return {
      'event': record.name,
      'kind': record.rawKind,
      'time': _isoTime(record),
      'properties': {for (final row in _rows(record)) row.key: row.value},
    };
  }

  static const _csvFixedColumns = ['#', 'recorded_at', 'kind', 'event'];

  static String _isoTime(MixpanelRecord record) => record.timestamp.toUtc().toIso8601String();

  static String _flatValue(Object? value) {
    if (value is Map || value is List) {
      return _compactJson.convert(value);
    }
    return formatPropertyValue(value);
  }

  static String _csvLine(List<String> fields) => '${fields.map(_csvField).join(',')}\r\n';

  static String _csvField(String field) {
    if (!field.contains(RegExp(r'[,"\r\n]'))) {
      return field;
    }
    return '"${field.replaceAll('"', '""')}"';
  }

  static String _markdownCell(String text) {
    return text.replaceAll('|', r'\|').replaceAll('\r\n', '<br>').replaceAll('\n', '<br>');
  }

  static Object? _toEncodable(Object? value) => value.toString();
}
