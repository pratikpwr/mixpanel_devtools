# mixpanel_devtools example

A demo app for the [mixpanel_devtools](https://pub.dev/packages/mixpanel_devtools) DevTools
extension. It sends one Mixpanel call of each kind at start-up, so that the Mixpanel tab has
data to show.

## Run the demo

```bash
flutter run --dart-define=AUTOPLAY=true
```

Open DevTools, then open the **mixpanel_devtools** tab.

Without `--dart-define=MIXPANEL_TOKEN=...` the demo opts out of tracking, so the native SDK
sends nothing to Mixpanel.

## The recorder

[`lib/mixpanel_devtools_recorder.dart`](lib/mixpanel_devtools_recorder.dart) is the file that
you copy into your own app. It has no dependency on `mixpanel_devtools`. Wrap the instance that
`Mixpanel.init` returns:

```dart
final mixpanel = await Mixpanel.init(token, trackAutomaticEvents: true);
final recorded = MixpanelDevtoolsRecorder.instrument(mixpanel, token: token);
```

In release builds, `instrument` returns `mixpanel` unchanged and records nothing.
