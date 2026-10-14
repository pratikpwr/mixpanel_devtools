import 'package:flutter/material.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

import 'mixpanel_devtools_recorder.dart';

/// Pass a real project token with `--dart-define=MIXPANEL_TOKEN=...` to send events to Mixpanel.
/// Without one, the demo opts out of tracking, so the native SDK sends nothing.
const _token = String.fromEnvironment('MIXPANEL_TOKEN', defaultValue: 'demo-token');

/// With `--dart-define=AUTOPLAY=true`, the demo presses each button once after start-up.
const _autoplay = bool.fromEnvironment('AUTOPLAY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mixpanel = await Mixpanel.init(
    _token,
    trackAutomaticEvents: false,
    optOutTrackingDefault: _token == 'demo-token',
  );
  runApp(DemoApp(mixpanel: MixpanelDevtoolsRecorder.instrument(mixpanel, token: _token)));
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key, required this.mixpanel});

  final Mixpanel mixpanel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mixpanel DevTools demo',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: DemoScreen(mixpanel: mixpanel),
    );
  }
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key, required this.mixpanel});

  final Mixpanel mixpanel;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  int _buttonTaps = 0;

  Mixpanel get _mixpanel => widget.mixpanel;

  @override
  void initState() {
    super.initState();
    if (_autoplay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playAll());
    }
  }

  Future<void> _playAll() async {
    for (final (_, action) in _actions) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      action();
    }
  }

  List<(String, VoidCallback)> get _actions {
    return [
      (
        'Register super properties',
        () => _mixpanel.registerSuperProperties({
          'feature_flags': ['new_checkout: true', 'search_v2: treatment', 'onboarding: variant_a'],
          'plan': 'pro',
          'is_trial': false,
        }),
      ),
      ('Identify user', () => _mixpanel.identify('demo-user-42')),
      ('People: set company', () => _mixpanel.getPeople().set('company_name', 'Acme')),
      ('Time "Page Viewed"', () => _mixpanel.timeEvent('Page Viewed')),
      ('Track Page Viewed', () => _mixpanel.track('Page Viewed', properties: {'page': 'home', 'locale': 'en-GB'})),
      (
        'Track Item Viewed',
        () => _mixpanel.track('Item Viewed', properties: {'item': 'Welcome banner', 'location': 'Home', 'position': 1}),
      ),
      (
        'Track Button Clicked',
        () => _mixpanel.track(
          'Button Clicked',
          properties: {'button': 'Checkout', 'tap_count': ++_buttonTaps, 'at': DateTime.now()},
        ),
      ),
      ('Flush', () => _mixpanel.flush()),
      ('Reset', () => _mixpanel.reset()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mixpanel DevTools demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Open DevTools, then the "mixpanel_devtools" tab. Each button sends one Mixpanel call.'),
          const SizedBox(height: 16),
          for (final (label, onPressed) in _actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.tonal(onPressed: onPressed, child: Text(label)),
            ),
        ],
      ),
    );
  }
}
