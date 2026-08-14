import 'package:flutter/material.dart';

import 'controllers/player_controller.dart';
import 'screens/player_screen.dart';

class AudioManagerExampleApp extends StatefulWidget {
  const AudioManagerExampleApp({super.key, this.controller});

  final PlayerController? controller;

  @override
  State<AudioManagerExampleApp> createState() => _AudioManagerExampleAppState();
}

class _AudioManagerExampleAppState extends State<AudioManagerExampleApp> {
  late final PlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PlayerController();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'audio_manager example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: PlayerScreen(controller: _controller),
    );
  }
}
