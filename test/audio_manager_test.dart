import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_manager/audio_manager.dart';

void main() {
  const MethodChannel channel = MethodChannel('audio_manager');

  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var startResponse = '';

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getPlatformVersion') return '42';
      if (methodCall.method == 'currentVolume') return 0.5;
      if (methodCall.method == 'start') return startResponse;
      if (methodCall.method == 'updateInfo') return '';
      if (methodCall.method == 'getState') {
        return {
          'isPlaying': false,
          'position': 1,
          'duration': 10,
          'title': 'state title',
          'desc': 'state desc',
          'url': 'state url',
        };
      }
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
      titleMaxLines: 2,
      showPreviousButton: true,
      showStopButton: false,
    );

    expect(result, '');
    expect(manager.info!.title, 'new');
    expect(manager.info!.desc, 'new desc');
    expect(manager.info!.coverUrl, 'new cover');
    expect(manager.info!.titleMaxLines, 2);
    expect(manager.info!.showPreviousButton, isTrue);
    expect(manager.info!.showStopButton, isFalse);
  });

  test('start surfaces native error and clears loading state', () async {
    startResponse = 'bad url';
    addTearDown(() => startResponse = '');

    final manager = AudioManager.instance;
    manager.nextMode(playMode: PlayMode.sequence);
    manager.audioList = [
      AudioInfo('url', title: 'title', desc: 'desc', coverUrl: 'cover'),
    ];

    final result = await manager.play(index: 0, auto: false);

    expect(result, 'bad url');
    expect(manager.error, 'bad url');
    expect(manager.isLoading, isFalse);
  });

  test('currentState returns native state', () async {
    final state = await AudioManager.instance.currentState();

    expect(state['title'], 'state title');
    expect(state['isPlaying'], isFalse);
  });
}
