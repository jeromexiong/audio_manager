import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:audio_manager/audio_manager.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  bool isPlaying = false;
  int _duration;
  int _position;
  num _slider;

  @override
  void initState() {
    super.initState();

    initPlatformState();

    setupAudio();
  }

  @override
  void dispose() {
    AudioManager.instance.stop();
    super.dispose();
  }

  void setupAudio() {
    AudioManager.instance
        .start(
            "assets/audio.mp3",
            // "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
            "title",
            desc: "desc",
            // cover: "assets/ic_launcher.png",
            cover:
                "https://cdn.jsdelivr.net/gh/flutterchina/website@1.0/images/flutter-mark-square-100.png")
        .then((err) {
      print(err);
    });

    AudioManager.instance.onEvents((events, args) {
      // print("$events, $args");
      switch (events) {
        case AudioManagerEvents.buffering:
          print("buffering $args");
          break;
        case AudioManagerEvents.playstatus:
          isPlaying = AudioManager.instance.isPlaying;
          setState(() {});
          break;
        case AudioManagerEvents.timeupdate:
          _duration = AudioManager.instance.duration;
          _position = AudioManager.instance.position;
          _slider = _position / _duration;
          setState(() {});
          AudioManager.instance.updateLrc(args["position"].toString());
          print(AudioManager.instance.info);
          break;
        case AudioManagerEvents.error:
          Scaffold.of(context).showSnackBar(
            SnackBar(
              content: Text(args),
            ),
          );
          break;
        case AudioManagerEvents.next:
          next();
          break;
        case AudioManagerEvents.previous:
          previous();
          break;
        default:
          break;
      }
    });
  }

  void next() {
    print("next audio");
  }

  void previous() {
    print("previous audio");
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      platformVersion = await AudioManager.instance.platformVersion;
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin audio player'),
        ),
        body: Center(
          child: Column(
            children: <Widget>[
              Text('Running on: $_platformVersion\n'),
              Expanded(child: Center(child: Text("lrc text: $_position"))),
              bottomPanel()
            ],
          ),
        ),
      ),
    );
  }

  Widget bottomPanel() {
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            IconButton(
              onPressed: () => previous(),
              icon: Icon(
                Icons.skip_previous,
                size: 32.0,
                color: Colors.black,
              ),
            ),
            IconButton(
              onPressed: () async {
                bool isPlaying = await AudioManager.instance.playOrPause();
                print("await -- $isPlaying");
              },
              padding: const EdgeInsets.all(0.0),
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                size: 48.0,
                color: Colors.black,
              ),
            ),
            IconButton(
              onPressed: () => next(),
              icon: Icon(
                Icons.skip_next,
                size: 32.0,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
      SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbColor: Colors.blueAccent,
            overlayColor: Colors.blue,
            thumbShape: RoundSliderThumbShape(
              disabledThumbRadius: 5,
              enabledThumbRadius: 5,
            ),
            overlayShape: RoundSliderOverlayShape(
              overlayRadius: 10,
            ),
            activeTrackColor: Colors.blueAccent,
            inactiveTrackColor: Colors.grey,
          ),
          child: Slider(
            value: _slider ?? 0,
            onChanged: (value) {
              setState(() {
                _slider = value;
              });
            },
            onChangeEnd: (value) {
              if (_duration != null) {
                int msec = (_duration * value).round();
                AudioManager.instance.seekTo(msec);
              }
            },
          )),
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        child: _timer(context),
      ),
    ]);
  }

  Widget _timer(BuildContext context) {
    var style = TextStyle(color: Colors.black);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        Text(
          _formatDuration(_position),
          style: style,
        ),
        Text(
          _formatDuration(_duration),
          style: style,
        ),
      ],
    );
  }

  String _formatDuration(int msec) {
    if (msec == null) return "--:--";
    Duration d = Duration(milliseconds: msec);
    int minute = d.inMinutes;
    int second = (d.inSeconds > 60) ? (d.inSeconds % 60) : d.inSeconds;
    String format = ((minute < 10) ? "0$minute" : "$minute") +
        ":" +
        ((second < 10) ? "0$second" : "$second");
    return format;
  }
}
