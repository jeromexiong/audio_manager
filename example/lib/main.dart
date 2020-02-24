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
  Duration _duration;
  Duration _position;
  num _slider;
  String _error;
  num curIndex = 0;

  @override
  void initState() {
    super.initState();

    initPlatformState();
  }

  @override
  void dispose() {
    // 释放所有资源
    AudioManager.instance.stop();
    super.dispose();
  }

  final list = [
    {
      "title": "Assets",
      "desc": "local assets playback",
      "url": "assets/audio.mp3",
      "cover": "assets/ic_launcher.png"
    },
    {
      "title": "network",
      "desc": "network resouce playback",
      "url": "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
      "cover":
          "https://cdn.jsdelivr.net/gh/flutterchina/website@1.0/images/flutter-mark-square-100.png"
    },
  ];

  void setupAudio(int idx) {
    final item = list[idx];
    curIndex = idx;

    AudioManager.instance
        .start(item["url"], item["title"],
            desc: item["desc"], cover: item["cover"])
        .then((err) {
      print(err);
    });

    AudioManager.instance.onEvents((events, args) {
      print("$events, $args");
      switch (events) {
        case AudioManagerEvents.ready:
          print("ready to play");
          AudioManager.instance.seekTo(Duration(seconds: 10));
          break;
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
          _slider = _position.inMilliseconds / _duration.inMilliseconds;
          setState(() {});
          AudioManager.instance.updateLrc(args["position"].toString());
          // print(AudioManager.instance.info);
          break;
        case AudioManagerEvents.error:
          _error = args;
          setState(() {});
          break;
        case AudioManagerEvents.next:
          next();
          break;
        case AudioManagerEvents.previous:
          previous();
          break;
        case AudioManagerEvents.ended:
          next();
          break;
        default:
          break;
      }
    });
  }

  void next() {
    print("next audio");
    int idx = (curIndex + 1) % list.length;
    setupAudio(idx);
  }

  void previous() {
    print("previous audio");
    int idx = curIndex - 1;
    idx = idx < 0 ? list.length - 1 : idx;
    setupAudio(idx);
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
              Expanded(
                child: ListView.separated(
                    itemBuilder: (context, item) {
                      return ListTile(
                        title: Text(list[item]["title"],
                            style: TextStyle(fontSize: 18)),
                        subtitle: Text(list[item]["desc"]),
                        onTap: () => setupAudio(item),
                      );
                    },
                    separatorBuilder: (BuildContext context, int index) =>
                        Divider(),
                    itemCount: list.length),
              ),
              Center(
                  child:
                      Text(_error != null ? _error : "lrc text: $_position")),
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
                String status = await AudioManager.instance.playOrPause();
                print("await -- $status");
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
                Duration msec = Duration(
                    milliseconds: (_duration.inMilliseconds * value).round());
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

  String _formatDuration(Duration d) {
    if (d == null) return "--:--";
    int minute = d.inMinutes;
    int second = (d.inSeconds > 60) ? (d.inSeconds % 60) : d.inSeconds;
    String format = ((minute < 10) ? "0$minute" : "$minute") +
        ":" +
        ((second < 10) ? "0$second" : "$second");
    return format;
  }
}
