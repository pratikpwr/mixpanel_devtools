/// The type of Mixpanel call that a [MixpanelRecord] describes.
enum RecordKind {
  track('track'),
  people('people'),
  group('group'),
  identity('identity'),
  superProperties('super'),
  timing('timing'),
  consent('consent'),
  flush('flush'),
  unknown('unknown');

  const RecordKind(this.wireName);

  /// The value of the `kind` field in the protocol.
  final String wireName;

  static RecordKind fromWire(String? value) {
    for (final kind in values) {
      if (kind.wireName == value && kind != unknown) {
        return kind;
      }
    }
    return unknown;
  }
}

/// One Mixpanel call that the app recorded.
class MixpanelRecord {
  const MixpanelRecord({
    required this.id,
    required this.runId,
    required this.timestamp,
    required this.kind,
    required this.rawKind,
    required this.name,
    required this.properties,
    this.superProperties,
    this.distinctId,
    this.groups,
  });

  /// Reads a record from protocol JSON. Missing or wrong-type fields get defaults.
  factory MixpanelRecord.fromJson(Map<Object?, Object?> json) {
    final rawKind = _string(json['kind']) ?? RecordKind.unknown.wireName;
    return MixpanelRecord(
      id: _int(json['id']) ?? 0,
      runId: _string(json['runId']) ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(_int(json['timestamp']) ?? 0),
      kind: RecordKind.fromWire(rawKind),
      rawKind: rawKind,
      name: _string(json['name']) ?? '',
      properties: _map(json['properties']) ?? const {},
      superProperties: _map(json['superProperties']),
      distinctId: _string(json['distinctId']),
      groups: _map(json['groups']),
    );
  }

  final int id;
  final String runId;
  final DateTime timestamp;
  final RecordKind kind;

  /// The `kind` value as the app sent it. It differs from [kind] only for unknown kinds.
  final String rawKind;

  /// The event name for `track`, or the operation name for other kinds.
  final String name;
  final Map<String, Object?> properties;
  final Map<String, Object?>? superProperties;
  final String? distinctId;
  final Map<String, Object?>? groups;

  /// Identifies the record across app runs.
  String get key => '$runId:$id';

  bool get isTrack => kind == RecordKind.track;

  String get label => isTrack ? name : '[$rawKind] $name';

  /// The protocol JSON of this record. [MixpanelRecord.fromJson] reads it back.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'runId': runId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'kind': rawKind,
      'name': name,
      'properties': properties,
      if (superProperties != null) 'superProperties': superProperties,
      if (distinctId != null) 'distinctId': distinctId,
      if (groups != null) 'groups': groups,
    };
  }
}

int? _int(Object? value) => value is num ? value.toInt() : null;

String? _string(Object? value) => value is String ? value : null;

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, nested) => MapEntry('$key', _normalize(nested)));
}

Object? _normalize(Object? value) {
  if (value is Map) {
    return _map(value);
  }
  if (value is List) {
    return value.map(_normalize).toList();
  }
  return value;
}
