import 'key_value_store_base.dart';

KeyValueStore createSessionStore() => MemoryKeyValueStore();

KeyValueStore createLocalStore() => MemoryKeyValueStore();
