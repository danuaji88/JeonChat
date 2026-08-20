import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jeonchat/services/api_service.dart';
import 'package:jeonchat/widgets/input_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Widget host({
    required void Function(String text, String model,
            {String? attachmentUrl, String? attachmentName, String? attachmentKind})
        onSend,
    required ValueNotifier<Map<String, dynamic>?> external,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: JeonChatInputBar(
          onSend: onSend,
          onGenerateImage: (_) {},
          onSearchWeb: (_) {},
          onDeepResearch: (_) {},
          onGenerateAudio: (_) {},
          onGenerateVideo: (_) {},
          onVoiceModeResult: (_) {},
          modelOptions: ApiService.fallbackModelOptions,
          onAnalyzeImage: (_, __) {},
          onWebSearch: (_) {},
          onUploadDoc: (_, __) {},
          onUploadAttachment: (name, bytes) async => {
            'name': name,
            'url': 'https://chat.jeonlive.com/uploads/$name',
            'size': bytes.length,
          },
          onFetchLibrary: () async => [],
          externalAttachment: external,
          onSpeechToText: (_) async => '',
        ),
      ),
    );
  }

  testWidgets('tapping the blue send button dispatches onSend with the attachment (does not just clear it)',
      (tester) async {
    final external = ValueNotifier<Map<String, dynamic>?>(null);
    String? sentText;
    String? sentAttachmentUrl;
    var sendCallCount = 0;

    await tester.pumpWidget(host(
      onSend: (text, model, {attachmentUrl, attachmentName, attachmentKind}) {
        sendCallCount++;
        sentText = text;
        sentAttachmentUrl = attachmentUrl;
      },
      external: external,
    ));
    await tester.pumpAndSettle();

    // Simulasikan attachment sudah terupload & pending (sama seperti hasil
    // Upload Gambar/File di popover "+", atau drag&drop).
    external.value = {'name': 'foto.png', 'url': 'https://chat.jeonlive.com/uploads/foto.png', 'size': 1234};
    await tester.pumpAndSettle();

    // Preview attachment harus muncul.
    expect(find.text('foto.png'), findsOneWidget);

    // Tombol kirim (panah biru, accent) harus tampil karena ada pending attachment.
    final sendButton = find.byIcon(Icons.arrow_upward_rounded);
    expect(sendButton, findsOneWidget, reason: 'tombol kirim (biru) harus tampil saat ada pending attachment');

    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(sendCallCount, 1, reason: 'onSend harus terpanggil TEPAT SEKALI saat tombol biru ditekan');
    expect(sentText, '');
    expect(sentAttachmentUrl, 'https://chat.jeonlive.com/uploads/foto.png',
        reason: 'attachment yang sudah diupload harus ikut dikirim ke onSend, bukan cuma dihapus');

    // Preview harus hilang SETELAH terkirim (draft cleared).
    expect(find.text('foto.png'), findsNothing);
  });

  testWidgets('tapping the dark X button clears the preview WITHOUT calling onSend', (tester) async {
    final external = ValueNotifier<Map<String, dynamic>?>(null);
    var sendCallCount = 0;

    await tester.pumpWidget(host(
      onSend: (text, model, {attachmentUrl, attachmentName, attachmentKind}) {
        sendCallCount++;
      },
      external: external,
    ));
    await tester.pumpAndSettle();

    external.value = {'name': 'dokumen.pdf', 'url': 'https://chat.jeonlive.com/uploads/dokumen.pdf', 'size': 5678};
    await tester.pumpAndSettle();

    expect(find.text('dokumen.pdf'), findsOneWidget);

    final cancelButton = find.byIcon(Icons.close_rounded);
    expect(cancelButton, findsOneWidget, reason: 'tombol batal (X gelap) di kotak preview harus ada');

    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(sendCallCount, 0, reason: 'onSend TIDAK BOLEH terpanggil saat tombol batal (X) ditekan');
    expect(find.text('dokumen.pdf'), findsNothing);
  });
}
