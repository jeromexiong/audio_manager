import 'package:audio_manager_example/app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the player screen', (WidgetTester tester) async {
    const channel = MethodChannel('audio_manager');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      switch (call.method) {
        case 'getPlatformVersion':
          return '42';
        case 'currentVolume':
          return 0.5;
        case 'start':
          return '';
        case 'updateInfo':
          return '';
        case 'getState':
          return {'title': 'state title'};
        default:
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const AudioManagerExampleApp());
    await tester.pump();

    expect(find.text('audio_manager example'), findsOneWidget);
  });
}
