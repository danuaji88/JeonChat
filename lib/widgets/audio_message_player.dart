import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Play/pause control for a TTS audio_url, rendered inside a chat bubble.
class AudioMessagePlayer extends StatefulWidget {
  final String url;

  const AudioMessagePlayer({super.key, required this.url});

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playerState = s);
    });
    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playerState == PlayerState.playing) {
        await _player.pause();
      } else {
        setState(() => _error = null);
        await _player.play(UrlSource(widget.url));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Gagal memutar audio');
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final playing = _playerState == PlayerState.playing;
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: JeonColors.surface3,
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(JeonRadius.small),
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _toggle,
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(color: JeonColors.accent, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 18,
                color: const Color(0xFF04150A),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: JeonColors.border,
                    valueColor: const AlwaysStoppedAnimation(JeonColors.accent),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _error ??
                      '${_fmt(_position)} / ${_duration.inMilliseconds == 0 ? '--:--' : _fmt(_duration)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: _error != null ? JeonColors.danger : JeonColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
