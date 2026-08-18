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

  /// Hasil runCode() dari Code Interpreter — {code, output} atau
  /// {code, error} — dirender sebagai blok kode + output di chat_bubble.dart.
  final Map<String, String>? codeResult;

  /// Nama dokumen sumber jawaban ini (dari askDoc()) — dirender sebagai
  /// badge "Dari dokumen: X" di atas bubble kalau tidak null.
  final String? docSource;

  /// ID plugin (snake_case, mis. "video_editor") yang dipakai backend buat
  /// menyusun balasan ini — dari field "plugins_used" respons /agent,
  /// dirender sebagai badge kecil "via X, Y" di chat_bubble.dart.
  final List<String> pluginsUsed;

  /// Nama skill yang baru disimpan otomatis oleh backend (AutoLearn) — sudah
  /// dilucuti dari [text] (lihat _extractAutoLearn di chat_screen.dart),
  /// dirender sebagai banner hijau khusus di chat_bubble.dart kalau tidak null.
  final String? autoLearnSkill;

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
    this.codeResult,
    this.docSource,
    this.pluginsUsed = const [],
    this.autoLearnSkill,
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
        if (codeResult != null) 'codeResult': codeResult,
        if (docSource != null) 'docSource': docSource,
        if (pluginsUsed.isNotEmpty) 'pluginsUsed': pluginsUsed,
        if (autoLearnSkill != null) 'autoLearnSkill': autoLearnSkill,
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
        codeResult: (json['codeResult'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())),
        docSource: json['docSource'] as String?,
        pluginsUsed: (json['pluginsUsed'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        autoLearnSkill: json['autoLearnSkill'] as String?,
      );
}
