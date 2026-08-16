import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme.dart';
import 'tool_card.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    final avatar = Container(
      width: 26,
      height: 26,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: isUser ? JeonColors.surface3 : null,
        border: isUser ? Border.all(color: JeonColors.border) : null,
        gradient: isUser
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [JeonColors.accent, JeonColors.accentDim],
              ),
      ),
      alignment: Alignment.center,
      child: Text(
        isUser ? 'AJ' : 'J',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isUser ? JeonColors.inkMuted : const Color(0xFF04150A),
        ),
      ),
    );

    final bubble = Flexible(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser ? JeonColors.surface3 : JeonColors.surface2,
          border: Border.all(color: JeonColors.borderSoft),
          borderRadius: BorderRadius.circular(JeonRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: const TextStyle(fontSize: 13.4, color: JeonColors.ink, height: 1.4),
            ),
            if (message.toolCall != null) ToolCardWidget(toolCall: message.toolCall!),
            if (message.costChip != null || message.timeChip != null)
              Container(
                margin: const EdgeInsets.only(top: 9),
                padding: const EdgeInsets.only(top: 9),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: JeonColors.borderSoft)),
                ),
                child: Row(
                  children: [
                    if (message.costChip != null) _chip(message.costChip!),
                    if (message.costChip != null && message.timeChip != null)
                      const SizedBox(width: 6),
                    if (message.timeChip != null) _chip(message.timeChip!),
                    const Spacer(),
                    Icon(Icons.copy, size: 14, color: JeonColors.inkFaint),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isUser
            ? [bubble, const SizedBox(width: 10), avatar]
            : [avatar, const SizedBox(width: 10), bubble],
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: JeonColors.surface,
          border: Border.all(color: JeonColors.borderSoft),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10.5,
            color: JeonColors.inkFaint,
          ),
        ),
      );
}
