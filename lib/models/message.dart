enum ToolCallStatus { running, done }

class ToolCall {
  final String scriptName;
  final String detail;
  final ToolCallStatus status;
  final int progressPercent;

  const ToolCall({
    required this.scriptName,
    required this.detail,
    required this.status,
    this.progressPercent = 0,
  });
}

class ChatMessage {
  final bool isUser;
  final String text;
  final ToolCall? toolCall;
  final String? costChip;
  final String? timeChip;

  const ChatMessage({
    required this.isUser,
    required this.text,
    this.toolCall,
    this.costChip,
    this.timeChip,
  });

  /// Shape expected by the JeonGPT-style backend: {role, content}.
  Map<String, dynamic> toApiJson() => {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
      };
}
