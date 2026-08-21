import 'package:flutter/material.dart';

import '../theme.dart';

/// Badge notifikasi (fase 3.3, Tugas Terjadwal) — ikon lonceng + angka
/// unread merah kecil. [count] <= 0 cuma menampilkan ikon lonceng polos
/// tanpa lingkaran merah.
class NotificationBadge extends StatelessWidget {
  final int count;
  final double iconSize;
  final Color? iconColor;
  final VoidCallback? onTap;

  const NotificationBadge({
    super.key,
    required this.count,
    this.iconSize = 18,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.notifications_outlined, size: iconSize, color: iconColor ?? JeonColors.inkMuted),
        if (count > 0)
          Positioned(
            right: -4,
            top: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              decoration: BoxDecoration(color: JeonColors.danger, borderRadius: BorderRadius.circular(999)),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
      ],
    );
    if (onTap == null) return badge;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(4), child: badge),
    );
  }
}
