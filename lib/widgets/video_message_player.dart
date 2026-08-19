import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';

/// Inline video player ala Gemini — video diputar langsung di dalam chat
/// bubble dengan kontrol: play/pause, mute/unmute, progress + scrub,
/// durasi, download, dan share.
class VideoMessagePlayer extends StatefulWidget {
  final String url;

  const VideoMessagePlayer({super.key, required this.url});

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _playing = false;
  bool _muted = false;
  bool _error = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _controller = c;
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _initialized = true;
        _muted = c.value.volume == 0;
      });
      c.addListener(_onTick);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = true);
    }
  }

  void _onTick() {
    if (!mounted || _controller == null) return;
    final c = _controller!;
    setState(() {
      _playing = c.value.isPlaying;
      _muted = c.value.volume == 0;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final c = _controller;
    if (c == null || !_initialized) return;
    try {
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        if (c.value.position >= c.value.duration) {
          await c.seekTo(Duration.zero);
        }
        await c.play();
      }
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;
    try {
      if (c.value.volume > 0) {
        await c.setVolume(0);
      } else {
        await c.setVolume(1.0);
      }
    } catch (_) {}
  }

  Future<void> _seek(double fraction) async {
    final c = _controller;
    if (c == null || c.value.duration.inMilliseconds == 0) return;
    final target = Duration(
        milliseconds:
            (c.value.duration.inMilliseconds * fraction).round());
    try {
      await c.seekTo(target);
    } catch (_) {}
  }

  Future<void> _download() async {
    try {
      await launchUrlString(widget.url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _share() async {
    try {
      await Share.share('Video JEON: ${widget.url}',
          subject: 'Video JEON');
    } catch (_) {
      // Web tanpa Web Share API / desktop — fallback salin URL.
      await Clipboard.setData(ClipboardData(text: widget.url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link video disalin ke clipboard')),
      );
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _hideTimer?.cancel();
    if (_controlsVisible && _playing) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _playing) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      // Fallback: kartu klikable (buka di tab baru) kalau player gagal.
      return Container(
        margin: const EdgeInsets.only(top: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _download,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: JeonColors.surface3,
              border: Border.all(color: JeonColors.borderSoft),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_outline,
                    size: 22, color: JeonColors.accent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Ketuk untuk buka video',
                      style: TextStyle(
                          fontSize: 12.5, color: JeonColors.ink)),
                ),
                const Icon(Icons.open_in_new,
                    size: 14, color: JeonColors.inkMuted),
              ],
            ),
          ),
        ),
      );
    }

    if (!_initialized) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        height: 180,
        decoration: BoxDecoration(
          color: JeonColors.surface3,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: JeonColors.accent)),
            SizedBox(height: 8),
            Text('Memuat video...',
                style:
                    TextStyle(fontSize: 11.5, color: JeonColors.inkFaint)),
          ],
        ),
      );
    }

    final c = _controller!;
    final progress = c.value.duration.inMilliseconds == 0
        ? 0.0
        : (c.value.position.inMilliseconds /
                c.value.duration.inMilliseconds)
            .clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JeonColors.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
        child: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              VideoPlayer(c),
              // Play/pause overlay tengah
              if (_controlsVisible)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _playing ? 0.0 : 1.0,
                  child: Center(
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _togglePlay,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 30,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              // Kontrol bawah (progress + durasi)
              if (_controlsVisible)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12),
                            activeTrackColor: JeonColors.accent,
                            inactiveTrackColor:
                                Colors.white.withValues(alpha: 0.3),
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: progress,
                            onChanged: (v) => _seek(v),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Text(
                                '${_fmt(c.value.position)} / ${_fmt(c.value.duration)}',
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.white,
                                    fontFamily: 'monospace'),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: _toggleMute,
                                child: Icon(
                                  _muted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  size: 17,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Tombol aksi atas-kanan (download & share)
              if (_controlsVisible)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      _actionCircle(
                          icon: Icons.file_download_outlined,
                          tooltip: 'Download',
                          onTap: _download),
                      const SizedBox(width: 6),
                      _actionCircle(
                          icon: Icons.share_outlined,
                          tooltip: 'Bagikan',
                          onTap: _share),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCircle(
      {required IconData icon,
      required String tooltip,
      required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
