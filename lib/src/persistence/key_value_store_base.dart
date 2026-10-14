/// A small string store. In the browser it is `sessionStorage` or `localStorage`.
abstract class KeyValueStore {
  String? read(String key);

  void write(String key, String value);
}

/// A [KeyValueStore] in memory, for tests and for platforms without browser storage.
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;
}
