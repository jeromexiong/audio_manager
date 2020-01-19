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

  @override
  void initState() {
    super.initState();
    initPlatformState();
    AudioManager.instance.onEvents((events, args) {
      print("$events, $args");
      switch (events) {
        case AudioManagerEvents.buffering:
          print("buffering");
          break;
        case AudioManagerEvents.playstatus:
          print("playstatus");
          break;
        case AudioManagerEvents.timeupdate:
          AudioManager.instance.updateLrc(args["position"].toString());
          break;
        case AudioManagerEvents.error:
          print("error");
          break;
        case AudioManagerEvents.next:
          print("next");
          break;
        case AudioManagerEvents.previous:
          print("previous");
          break;
        default:
          break;
      }
    });
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

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
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
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            children: <Widget>[
              Text('Running on: $_platformVersion\n'),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(
                    icon: Icon(Icons.play_circle_outline),
                    onPressed: () {
                      AudioManager.instance
                          .start(
                              // "assets/audio.mp3",
                              "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
                              "title",
                              desc: "desc",
                              // cover: "assets/ic_launcher.png",
                              cover:
                                  "https://cdn.jsdelivr.net/gh/flutterchina/website@1.0/images/flutter-mark-square-100.png")
                          .then((err) {
                        print(err);
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.pause_circle_outline),
                    onPressed: () async {
                      bool isPlaying =
                          await AudioManager.instance.playOrPause();
                      print("await -- $isPlaying");
                      print("instance -- ${AudioManager.instance.isPlaying}");
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.stop),
                    onPressed: () {
                      AudioManager.instance.stop();
                    },
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
