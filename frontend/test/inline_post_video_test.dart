import 'dart:async';

import 'package:believers_palace/widgets/inline_post_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  testWidgets('autoplays muted and pauses and mutes offscreen', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final previousPlatform = VideoPlayerPlatform.instance;
    final platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previousPlatform);

    final visibility = VisibilityDetectorController.instance;
    final previousInterval = visibility.updateInterval;
    visibility.updateInterval = Duration.zero;
    addTearDown(() => visibility.updateInterval = previousInterval);

    final scroll = ScrollController();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
        body: ListView(
          controller: scroll,
          children: [
            InlinePostVideo(url: Uri.parse('https://example.test/post.mp4')),
            const SizedBox(height: 1600),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause video'), findsOneWidget);
    expect(platform.playing, isTrue);
    expect(platform.volume, 0);

    await tester.tap(find.byTooltip('Unmute video'));
    await tester.pumpAndSettle();
    expect(platform.volume, 1);

    await tester.tap(find.byTooltip('Pause video'));
    await tester.pumpAndSettle();
    expect(platform.playing, isFalse);
    await tester.tap(find.byTooltip('Play video'));
    await tester.pumpAndSettle();
    expect(platform.playing, isTrue);

    scroll.jumpTo(200);
    await tester.pumpAndSettle();
    expect(platform.playing, isTrue);
    scroll.jumpTo(420);
    await tester.pumpAndSettle();
    expect(platform.playing, isFalse);
    expect(platform.volume, 0);

    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(platform.playing, isTrue);
    expect(platform.volume, 0);

    await tester.tap(find.byTooltip('Unmute video'));
    await tester.pumpAndSettle();
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Another screen')),
    ));
    await tester.pumpAndSettle();
    expect(platform.playing, isFalse);
    expect(platform.volume, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(platform.playing, isTrue);
    expect(platform.volume, 0);

    await tester.tap(find.byTooltip('Unmute video'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(platform.playing, isFalse);
    expect(platform.volume, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.playing, isTrue);
    expect(platform.volume, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(InlinePostVideo), findsNothing);
  });
}

class _VideoPlatform extends VideoPlayerPlatform {
  final _events = StreamController<VideoEvent>();
  bool playing = false;
  double volume = 1;

  @override
  Future<void> init() async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    _events.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 30),
      size: const Size(1280, 720),
    ));
    return _events.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => playing = true;

  @override
  Future<void> pause(int playerId) async => playing = false;

  @override
  Future<void> setVolume(int playerId, double nextVolume) async {
    volume = nextVolume;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();

  @override
  Future<void> dispose(int playerId) => _events.close();
}
