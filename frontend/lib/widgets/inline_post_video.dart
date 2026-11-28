import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../l10n/app_locale.dart';

class InlinePostVideo extends StatefulWidget {
  const InlinePostVideo({super.key, required this.url});

  final Uri url;

  @override
  State<InlinePostVideo> createState() => _InlinePostVideoState();
}

class _InlinePostVideoState extends State<InlinePostVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _inView = false;
  bool _routeActive = false;
  bool _appActive = true;
  bool _pausedByUser = false;
  bool _muted = true;
  bool _ready = false;
  bool _failed = false;
  bool _syncing = false;
  bool _needsSync = false;

  bool get _active => _inView && _routeActive && _appActive;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    _appActive = binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    binding.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    _updatePlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _updatePlayback();
  }

  void _onVisibilityChanged(VisibilityInfo visibility) {
    if (!mounted) return;
    // Keep playback stable while the user scrolls near the autoplay boundary.
    final inView = visibility.visibleFraction >= (_inView ? 0.4 : 0.6);
    if (_inView == inView) return;
    _inView = inView;
    _updatePlayback();
  }

  void _updatePlayback() {
    if (!_active) _muted = true;
    if (_failed) return;
    if (_controller == null) {
      if (_active) unawaited(_load());
      return;
    }
    if (_ready) unawaited(_syncPlayback());
  }

  Future<void> _load() async {
    final controller = VideoPlayerController.networkUrl(
      widget.url,
      // This widget handles lifecycle changes so the plugin does not resume a
      // video that has since been scrolled away or manually paused.
      videoPlayerOptions: VideoPlayerOptions(
        allowBackgroundPlayback: true,
        mixWithOthers: true,
      ),
    );
    setState(() => _controller = controller);
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setVolume(0);
      if (!mounted) return;
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() => _ready = true);
      _updatePlayback();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _syncPlayback() async {
    _needsSync = true;
    if (_syncing) return;
    _syncing = true;
    final controller = _controller!;
    try {
      while (mounted && _needsSync) {
        _needsSync = false;
        if ((!_active || _pausedByUser) && controller.value.isPlaying) {
          await controller.pause();
          if (!mounted) return;
        }
        final volume = _muted ? 0.0 : 1.0;
        if (controller.value.volume != volume) {
          await controller.setVolume(volume);
          if (!mounted) return;
        }
        if (_active && !_pausedByUser && !controller.value.isPlaying) {
          await controller.play();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _syncing = false;
    }
  }

  void _retry() {
    final controller = _controller;
    setState(() {
      _ready = false;
      _failed = false;
      _controller = null;
      _muted = true;
    });
    if (controller != null) unawaited(controller.dispose());
    _updatePlayback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final aspectRatio = _ready ? controller!.value.aspectRatio : 16 / 9;
    final maxHeight = min(420.0, MediaQuery.sizeOf(context).height * 0.65);
    return VisibilityDetector(
      key: ObjectKey(this),
      onVisibilityChanged: _onVisibilityChanged,
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: double.infinity,
          height: min(maxHeight, constraints.maxWidth / aspectRatio),
          child: ColoredBox(
            color: Colors.black,
            child: _failed
                ? _unavailable(context)
                : _ready && controller != null
                    ? ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: controller,
                        builder: (context, value, _) => value.hasError
                            ? _unavailable(context)
                            : _player(context, controller, value),
                      )
                    : Center(
                        child: controller == null
                            ? const Icon(Icons.videocam_outlined,
                                color: Colors.white70)
                            : const CircularProgressIndicator(
                                color: Colors.white70),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _unavailable(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('Video unavailable'),
                style: const TextStyle(color: Colors.white)),
            TextButton(
              onPressed: _retry,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(context.tr('Retry')),
            ),
          ],
        ),
      );

  Widget _player(
    BuildContext context,
    VideoPlayerController controller,
    VideoPlayerValue value,
  ) =>
      Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ColoredBox(
              color: Colors.black54,
              child: Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    tooltip: context
                        .tr(value.isPlaying ? 'Pause video' : 'Play video'),
                    icon:
                        Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () {
                      _pausedByUser = value.isPlaying;
                      _updatePlayback();
                    },
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                    ),
                  ),
                  IconButton(
                    color: Colors.white,
                    tooltip: context
                        .tr(value.volume == 0 ? 'Unmute video' : 'Mute video'),
                    icon: Icon(
                        value.volume == 0 ? Icons.volume_off : Icons.volume_up),
                    onPressed: () {
                      _muted = value.volume > 0;
                      _updatePlayback();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}
