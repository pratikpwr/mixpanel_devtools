import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'connection/app_connection.dart';
import 'connection/vm_app_connection.dart';
import 'persistence/key_value_store.dart';
import 'persistence/records_persistence.dart';
import 'platform/file_download.dart';
import 'records_controller.dart';
import 'ui/mixpanel_screen.dart';

/// The root widget of the Mixpanel DevTools extension.
class MixpanelDevtoolsExtension extends StatelessWidget {
  const MixpanelDevtoolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(child: _ExtensionBody());
  }
}

class _ExtensionBody extends StatefulWidget {
  const _ExtensionBody();

  @override
  State<_ExtensionBody> createState() => _ExtensionBodyState();
}

class _ExtensionBodyState extends State<_ExtensionBody> {
  final _controller = RecordsController();
  late final _connection = VmAppConnection(serviceManager);
  late final RecordsPersistence _persistence;

  @override
  void initState() {
    super.initState();
    _persistence = RecordsPersistence(
      store: createSessionStore(),
      preferences: createLocalStore(),
      controller: _controller,
    );
    _connection.status.addListener(_attachPersistence);
    _attachPersistence();
  }

  @override
  void dispose() {
    _connection.status.removeListener(_attachPersistence);
    _persistence.dispose();
    _connection.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _attachPersistence() {
    final serviceUri = serviceManager.serviceUri;
    if (_connection.status.value == ConnectionStatus.disconnected || serviceUri == null) {
      return;
    }
    _persistence.attach(serviceUri);
  }

  @override
  Widget build(BuildContext context) {
    return MixpanelScreen(
      controller: _controller,
      connection: _connection,
      copyToClipboard: (text, message) => extensionManager.copyToClipboard(text, successMessage: message),
      download: downloadTextFile,
    );
  }
}
