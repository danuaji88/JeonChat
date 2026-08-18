import 'package:flutter/material.dart';

import '../theme.dart';

/// "AI sedang mengetik..." bubble — three pulsing dots shown while a
/// reply is in flight.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [JeonColors.accent, JeonColors.accentDim],
              ),
              boxShadow: [BoxShadow(color: JeonColors.accentGlow, blurRadius: 8)],
            ),
            alignment: Alignment.center,
            child: const Text('J',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF04150A))),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: JeonColors.surface2,
              border: Border.all(color: JeonColors.borderSoft),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(JeonRadius.bubble),
                topRight: Radius.circular(JeonRadius.bubble),
                bottomRight: Radius.circular(JeonRadius.bubble),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final t = (_controller.value - i * 0.2) % 1.0;
                    final scale = (t < 0.5 ? (0.6 + t) : (1.6 - t)).clamp(0.6, 1.1);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: JeonColors.inkFaint),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
