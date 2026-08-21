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

/// Kode/dokumen panjang terdeteksi backend di sebuah balasan /chat (fase
/// 3.1, lihat has_artifact/artifacts di ApiService.sendChat) — dirender
/// sebagai kartu ringkas di chat_bubble.dart, isi lengkapnya dibuka lewat
/// ArtifactPanel (lihat artifact_panel.dart).
class Artifact {
  final String type; // 'code' | 'document'
  final String language;
  final String languageLabel;
  final String title;
  final String content;
  final int start;
  final int end;

  const Artifact({
    required this.type,
    this.language = '',
    this.languageLabel = '',
    this.title = '',
    required this.content,
    this.start = 0,
    this.end = 0,
  });

  factory Artifact.fromApiJson(Map<String, dynamic> json) => Artifact(
        type: (json['type'] ?? 'code').toString(),
        language: (json['language'] ?? '').toString(),
        languageLabel: (json['language_label'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
        start: json['start'] as int? ?? 0,
        end: json['end'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'language': language,
        'languageLabel': languageLabel,
        'title': title,
        'content': content,
        'start': start,
        'end': end,
      };

  factory Artifact.fromJson(Map<String, dynamic> json) => Artifact(
        type: (json['type'] ?? 'code').toString(),
        language: (json['language'] ?? '').toString(),
        languageLabel: (json['languageLabel'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
        start: json['start'] as int? ?? 0,
        end: json['end'] as int? ?? 0,
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

  /// Lampiran non-gambar yang DIUPLOAD USER sendiri lewat menu "+" (Upload
  /// File/Dokumen atau Tambah dari Library) — beda dari [filePath] yang
  /// khusus file hasil BUATAN agent di server (lihat chat_bubble.dart
  /// _fileCard vs _attachmentCard, wordingnya beda). Lampiran gambar dari
  /// user tetap pakai [imageUrl] (sudah generik, tidak perlu field baru).
  final String? attachmentUrl;
  final String? attachmentName;

  /// True untuk balasan AI dari analyzeImage() — dipakai chat_bubble.dart
  /// buat kasih warna bubble hijau, beda dari balasan biasa.
  final bool isAnalysis;

  /// Hasil webSearch(), tiap item {title, url, snippet} — dirender sebagai
  /// daftar link clickable di chat_bubble.dart. Null/kosong = bukan pesan
  /// hasil pencarian.
  final List<Map<String, String>>? searchResults;

  /// Daftar sumber riset mendalam (dari /research) — tiap item
  /// {title, url, snippet}. Dirender sebagai kartu "Sumber [n]" di
  /// chat_bubble.dart di bawah jawaban ber-sitasi.
  final List<Map<String, String>>? researchSources;

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

  /// Artifact (kode/dokumen panjang) terdeteksi backend pada balasan ini
  /// (fase 3.1) — dirender sebagai kartu di bawah teks, isi lengkap dibuka
  /// lewat ArtifactPanel. Kosong = balasan biasa, tidak berubah.
  final List<Artifact> artifacts;

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
    this.attachmentUrl,
    this.attachmentName,
    this.isAnalysis = false,
    this.searchResults,
    this.researchSources,
    this.codeResult,
    this.docSource,
    this.pluginsUsed = const [],
    this.autoLearnSkill,
    this.artifacts = const [],
  });

  /// Shape expected by the JEON backend: {role, content}. Kalau pesan ini
  /// punya lampiran (imageUrl/attachmentUrl dari Upload Gambar/Video/File di
  /// menu "+"), URL-nya disisipkan juga sebagai teks di content (jaring
  /// pengaman — sama seperti catatan [Lampiran: ...] di _send() chat_screen.
  /// dart) SEKALIGUS sebagai field JSON terpisah, supaya konteks lampiran
  /// tidak hilang saat pesan ini ikut terkirim lewat riwayat /chat (mis.
  /// regenerate, cek biaya, atau fallback dari /agent yang timeout/gagal).
  Map<String, dynamic> toApiJson() {
    final url = imageUrl ?? attachmentUrl;
    final hasAttachment = url != null && url.isNotEmpty;
    return {
      'role': isUser ? 'user' : 'assistant',
      'content': hasAttachment ? '$text\n[Lampiran: ${attachmentName ?? 'file'} - $url]' : text,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
      if (attachmentUrl != null && attachmentUrl!.isNotEmpty) 'attachment_url': attachmentUrl,
      if (attachmentName != null && attachmentName!.isNotEmpty) 'attachment_name': attachmentName,
    };
  }

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
        if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
        if (attachmentName != null) 'attachmentName': attachmentName,
        if (isAnalysis) 'isAnalysis': isAnalysis,
        if (searchResults != null) 'searchResults': searchResults,
        if (researchSources != null) 'researchSources': researchSources,
        if (codeResult != null) 'codeResult': codeResult,
        if (docSource != null) 'docSource': docSource,
        if (pluginsUsed.isNotEmpty) 'pluginsUsed': pluginsUsed,
        if (autoLearnSkill != null) 'autoLearnSkill': autoLearnSkill,
        if (artifacts.isNotEmpty) 'artifacts': artifacts.map((a) => a.toJson()).toList(),
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
        attachmentUrl: json['attachmentUrl'] as String?,
        attachmentName: json['attachmentName'] as String?,
        isAnalysis: json['isAnalysis'] as bool? ?? false,
        searchResults: (json['searchResults'] as List?)
            ?.whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
            .toList(),
        researchSources: (json['researchSources'] as List?)
            ?.whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
            .toList(),
        codeResult: (json['codeResult'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())),
        docSource: json['docSource'] as String?,
        pluginsUsed: (json['pluginsUsed'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        autoLearnSkill: json['autoLearnSkill'] as String?,
        artifacts: (json['artifacts'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(Artifact.fromJson)
                .toList() ??
            const [],
      );
}
