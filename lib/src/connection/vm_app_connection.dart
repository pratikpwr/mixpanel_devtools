import 'dart:async';

import 'package:devtools_app_shared/service.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import '../models/mixpanel_record.dart';
import '../protocol.dart';
import 'app_connection.dart';

/// An [AppConnection] on the VM service that DevTools is connected to.
///
/// It reads the VM `Isolate` and `Extension` streams directly. The DevTools service extension
/// cache drops its listeners on hot restart, so this class does not depend on it.
class VmAppConnection implements AppConnection {
  VmAppConnection(this._serviceManager) {
    _serviceManager.connectedState.addListener(_onConnectedStateChanged);
    _onConnectedStateChanged();
  }

  final ServiceManager _serviceManager;
  final _status = ValueNotifier(ConnectionStatus.disconnected);
  final _liveRecords = StreamController<MixpanelRecord>.broadcast();
  final _backlogs = StreamController<List<MixpanelRecord>>.broadcast();
  final _subscriptions = <StreamSubscription<Event>>[];

  /// The isolate that registered the recorder.
  String? _isolateId;

  @override
  ValueListenable<ConnectionStatus> get status => _status;

  @override
  Stream<MixpanelRecord> get liveRecords => _liveRecords.stream;

  @override
  Stream<List<MixpanelRecord>> get backlogs => _backlogs.stream;

  @override
  Future<void> clear() => _call(MixpanelDevtoolsProtocol.clearMethod);

  @override
  Future<void> flush() => _call(MixpanelDevtoolsProtocol.flushMethod);

  @override
  void dispose() {
    _serviceManager.connectedState.removeListener(_onConnectedStateChanged);
    _cancelSubscriptions();
    _status.dispose();
    unawaited(_liveRecords.close());
    unawaited(_backlogs.close());
  }

  void _onConnectedStateChanged() {
    _cancelSubscriptions();
    _isolateId = null;
    final service = _serviceManager.service;
    if (!_serviceManager.connectedState.value.connected || service == null) {
      _status.value = ConnectionStatus.disconnected;
      return;
    }
    _status.value = ConnectionStatus.notInstrumented;
    _subscriptions
      ..add(service.onExtensionEvent.listen(_onExtensionEvent))
      ..add(service.onIsolateEvent.listen(_onIsolateEvent));
    unawaited(_findInstrumentedIsolate(service));
  }

  void _onExtensionEvent(Event event) {
    if (event.extensionKind != MixpanelDevtoolsProtocol.recordEventKind) {
      return;
    }
    final data = event.extensionData?.data;
    if (data == null) {
      return;
    }
    _isolateId ??= event.isolate?.id;
    _status.value = ConnectionStatus.ready;
    _liveRecords.add(MixpanelRecord.fromJson(data));
  }

  void _onIsolateEvent(Event event) {
    final isolateId = event.isolate?.id;
    if (event.kind == EventKind.kServiceExtensionAdded &&
        event.extensionRPC == MixpanelDevtoolsProtocol.getRecordsMethod &&
        isolateId != null) {
      unawaited(_loadBacklog(isolateId));
      return;
    }
    if (event.kind == EventKind.kIsolateExit && isolateId == _isolateId) {
      _isolateId = null;
      _status.value = ConnectionStatus.notInstrumented;
    }
  }

  Future<void> _findInstrumentedIsolate(VmService service) async {
    try {
      final vm = await service.getVM();
      for (final ref in vm.isolates ?? const <IsolateRef>[]) {
        final id = ref.id;
        if (id == null) {
          continue;
        }
        final isolate = await service.getIsolate(id);
        if (isolate.extensionRPCs?.contains(MixpanelDevtoolsProtocol.getRecordsMethod) ?? false) {
          await _loadBacklog(id);
          return;
        }
      }
    } on Object catch (error) {
      debugPrint('mixpanel_devtools: could not read the isolates: $error');
    }
  }

  Future<void> _loadBacklog(String isolateId) async {
    final service = _serviceManager.service;
    if (service == null) {
      return;
    }
    try {
      final response = await service.callServiceExtension(
        MixpanelDevtoolsProtocol.getRecordsMethod,
        isolateId: isolateId,
      );
      _isolateId = isolateId;
      _status.value = ConnectionStatus.ready;
      final records = response.json?['records'];
      if (records is List) {
        _backlogs.add([
          for (final record in records.whereType<Map<Object?, Object?>>()) MixpanelRecord.fromJson(record),
        ]);
      }
    } on Object catch (error) {
      debugPrint('mixpanel_devtools: could not load the records: $error');
    }
  }

  Future<void> _call(String method) async {
    final service = _serviceManager.service;
    final isolateId = _isolateId;
    if (service == null || isolateId == null) {
      return;
    }
    try {
      await service.callServiceExtension(method, isolateId: isolateId);
    } on Object catch (error) {
      debugPrint('mixpanel_devtools: $method failed: $error');
    }
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}
