import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_manager/audio_manager.dart';

void main() {
  const MethodChannel channel = MethodChannel('audio_manager');

  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getPlatformVersion') return '42';
      if (methodCall.method == 'currentVolume') return 0.5;
      if (methodCall.method == 'start') return '';
      if (methodCall.method == 'updateInfo') return '';
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await AudioManager.instance.platformVersion, '42');
  });

  test('shuffle visits every remaining track before repeating', () async {
    final manager = AudioManager.instance;
    manager.nextMode(playMode: PlayMode.shuffle);
    manager.audioList = List.generate(
      5,
      (index) => AudioInfo('url$index',
          title: 'title$index', desc: 'desc$index', coverUrl: 'cover$index'),
    );

    final visited = <int>{manager.curIndex};
    for (var i = 0; i < 4; i++) {
      await manager.next();
      visited.add(manager.curIndex);
    }

    expect(visited, hasLength(5));
  });

  test('updateInfo updates current metadata and forwards native call', () async {
    final manager = AudioManager.instance;
    manager.nextMode(playMode: PlayMode.sequence);
    manager.audioList = [
      AudioInfo('url', title: 'old', desc: 'old', coverUrl: 'old-cover'),
    ];

    final ready = const StandardMethodCodec()
        .encodeMethodCall(const MethodCall('ready', 1000));
    await messenger.handlePlatformMessage('audio_manager', ready, (_) {});

    final result = await manager.updateInfo(
      title: 'new',
      desc: 'new desc',
      coverUrl: 'new cover',
    );

    expect(result, '');
    expect(manager.info!.title, 'new');
    expect(manager.info!.desc, 'new desc');
    expect(manager.info!.coverUrl, 'new cover');
  });
}
