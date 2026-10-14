import 'package:web/web.dart' as web;

import 'key_value_store_base.dart';

/// Survives a page reload. Each DevTools browser tab has its own copy.
KeyValueStore createSessionStore() => _BrowserStore(() => web.window.sessionStorage);

/// Survives closing the browser. All DevTools tabs share it.
KeyValueStore createLocalStore() => _BrowserStore(() => web.window.localStorage);

class _BrowserStore implements KeyValueStore {
  _BrowserStore(this._storage);

  final web.Storage Function() _storage;

  @override
  String? read(String key) => _storage().getItem(key);

  @override
  void write(String key, String value) => _storage().setItem(key, value);
}
