import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import '../services/api_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';

/// "Kuota habis" popup — shown when a free/guest user hits the demo
/// message limit, or when tapped from the profile menu's "Upgrade plan".
Future<void> showUpgradeDialog(
  BuildContext context, {
  required ApiService api,
  required ProfileService profile,
  String message = 'Kamu sudah mencapai batas pesan gratis untuk sesi ini.',
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: JeonColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: JeonColors.warn.withValues(alpha: 0.15), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.bolt_rounded, color: JeonColors.warn, size: 22),
            ),
            const SizedBox(height: 14),
            const Text('Kuota Habis', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: JeonColors.ink)),
            const SizedBox(height: 6),
            Text(message, style: const TextStyle(fontSize: 12.8, color: JeonColors.inkFaint, height: 1.4)),
            const SizedBox(height: 4),
            const Text('Upgrade ke paket Bisnis atau Kreator untuk lanjut tanpa batas.',
                style: TextStyle(fontSize: 12.8, color: JeonColors.inkFaint, height: 1.4)),
            const SizedBox(height: 20),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SettingsScreen(api: api, profile: profile, initialCategory: SettingsCategory.billing),
                  ));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: JeonColors.accent,
                  foregroundColor: const Color(0xFF04150A),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
                ),
                child: const Text('Upgrade Sekarang', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Nanti Saja', style: TextStyle(fontSize: 13, color: JeonColors.inkMuted)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
