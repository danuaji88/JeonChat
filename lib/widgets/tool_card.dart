import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme.dart';

class ToolCardWidget extends StatelessWidget {
  final ToolCall toolCall;

  const ToolCardWidget({super.key, required this.toolCall});

  @override
  Widget build(BuildContext context) {
    final isRunning = toolCall.status == ToolCallStatus.running;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: JeonColors.surface,
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(JeonRadius.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: JeonColors.borderSoft)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt, size: 13, color: JeonColors.inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    toolCall.scriptName,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: JeonColors.inkMuted,
                    ),
                  ),
                ),
                Text(
                  isRunning
                      ? 'RUNNING · ${toolCall.progressPercent}%'
                      : 'DONE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: isRunning ? JeonColors.accent : JeonColors.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Text(
              toolCall.detail,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: JeonColors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
