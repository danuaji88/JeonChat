import 'package:flutter/material.dart';

import '../theme.dart';

/// Aksen hijau khusus dialog ini (spek desain: #10b981) — beda dari
/// JeonColors.accent (biru) yang dipakai di seluruh app, tapi dipertahankan
/// di sini karena tiap tier punya warna identitasnya sendiri dan #10b981
/// eksplisit diminta sebagai aksen utama dialog pemilihan tier.
const _tierAccent = Color(0xFF10B981);
const _tierMedium = JeonColors.warn;
const _tierPremium = Color(0xFFA371F7);

class _TierOption {
  final String value;
  final String emoji;
  final String label;
  final String priceLabel;
  final String description;
  final Color color;

  const _TierOption({
    required this.value,
    required this.emoji,
    required this.label,
    required this.priceLabel,
    required this.description,
    required this.color,
  });
}

const _tiers = [
  _TierOption(
    value: 'free',
    emoji: '🟢',
    label: 'Gratis',
    priceLabel: 'Rp0',
    description: 'Stok Openverse/Wikimedia/Pollinations',
    color: _tierAccent,
  ),
  _TierOption(
    value: 'cheap',
    emoji: '🔵',
    label: 'Murah',
    priceLabel: '~Rp50 - Rp200',
    description: 'Fal.ai Schnell / Novita / Gemini Veo Lite',
    color: JeonColors.accent,
  ),
  _TierOption(
    value: 'medium',
    emoji: '🟡',
    label: 'Sedang',
    priceLabel: '~Rp500 - Rp2.000',
    description: 'Fal.ai Dev / Kie.ai Veo3',
    color: _tierMedium,
  ),
  _TierOption(
    value: 'premium',
    emoji: '💎',
    label: 'Mahal',
    priceLabel: 'Custom / Approval',
    description: 'Kualitas sinematik tinggi',
    color: _tierPremium,
  ),
];

/// Dialog pilih tier biaya untuk pembuatan gambar/video. Dipanggil sebelum
/// eksekusi /media/image, /media/video, /image, atau /video. Return salah
/// satu dari 'free'/'cheap'/'medium'/'premium', atau null kalau user batal
/// (tap di luar sheet / tombol close).
Future<String?> showTierSelectionDialog(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: JeonColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => const TierSelectionSheet(),
  );
}

class TierSelectionSheet extends StatelessWidget {
  const TierSelectionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pilih Kualitas & Biaya',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: JeonColors.ink),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: JeonColors.inkMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pilih tier sesuai budget & kebutuhan kualitas kamu.',
              style: TextStyle(fontSize: 13, color: JeonColors.inkFaint),
            ),
            const SizedBox(height: 16),
            for (final tier in _tiers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TierCard(tier: tier),
              ),
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final _TierOption tier;

  const _TierCard({required this.tier});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).pop(tier.value),
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JeonColors.ink.withValues(alpha: 0.04),
          border: Border.all(color: tier.color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tier.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(tier.emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tier.label,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: JeonColors.ink),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tier.priceLabel,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: tier.color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tier.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: JeonColors.inkFaint),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: JeonColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
