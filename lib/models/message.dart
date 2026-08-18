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

  Map<String, dynamic> toJson() => {
        'scriptName': scriptName,
        'detail': detail,
        'status': status.name,
        'progressPercent': progressPercent,
      };

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        scriptName: json['scriptName'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        status: ToolCallStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => ToolCallStatus.done,
        ),
        progressPercent: json['progressPercent'] as int? ?? 0,
      );
}

class ChatMessage {
  final bool isUser;
  final String text;
  final ToolCall? toolCall;
  final String? costChip;
  final String? timeChip;
  final String? imageUrl;
  final String? audioUrl;
  final String? videoUrl;
  final String? filePath;

  /// True untuk balasan AI dari analyzeImage() — dipakai chat_bubble.dart
  /// buat kasih warna bubble hijau, beda dari balasan biasa.
  final bool isAnalysis;

  /// Hasil webSearch(), tiap item {title, url, snippet} — dirender sebagai
  /// daftar link clickable di chat_bubble.dart. Null/kosong = bukan pesan
  /// hasil pencarian.
  final List<Map<String, String>>? searchResults;

  const ChatMessage({
    required this.isUser,
    required this.text,
    this.toolCall,
    this.costChip,
    this.timeChip,
    this.imageUrl,
    this.audioUrl,
    this.videoUrl,
    this.filePath,
    this.isAnalysis = false,
    this.searchResults,
  });

  /// Shape expected by the JEON backend: {role, content}.
  Map<String, dynamic> toApiJson() => {
        'role': isUser ? 'user' : 'assistant',
        'content': text,
      };

  /// Local persistence shape — round-trips through ChatHistoryService.
  Map<String, dynamic> toJson() => {
        'isUser': isUser,
        'text': text,
        if (toolCall != null) 'toolCall': toolCall!.toJson(),
        if (costChip != null) 'costChip': costChip,
        if (timeChip != null) 'timeChip': timeChip,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (audioUrl != null) 'audioUrl': audioUrl,
        if (videoUrl != null) 'videoUrl': videoUrl,
        if (filePath != null) 'filePath': filePath,
        if (isAnalysis) 'isAnalysis': isAnalysis,
        if (searchResults != null) 'searchResults': searchResults,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        isUser: json['isUser'] as bool? ?? false,
        text: (json['text'] ?? '').toString(),
        toolCall: json['toolCall'] is Map<String, dynamic>
            ? ToolCall.fromJson(json['toolCall'] as Map<String, dynamic>)
            : null,
        costChip: json['costChip'] as String?,
        timeChip: json['timeChip'] as String?,
        imageUrl: json['imageUrl'] as String?,
        audioUrl: json['audioUrl'] as String?,
        videoUrl: json['videoUrl'] as String?,
        filePath: json['filePath'] as String?,
        isAnalysis: json['isAnalysis'] as bool? ?? false,
        searchResults: (json['searchResults'] as List?)
            ?.whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
            .toList(),
      );
}
