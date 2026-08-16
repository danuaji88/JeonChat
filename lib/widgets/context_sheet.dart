import 'package:flutter/material.dart';

import '../models/agent.dart';
import '../theme.dart';

class ContextSheet extends StatelessWidget {
  final List<TaskItem> tasks;
  final List<KpiItem> kpis;
  final List<IntegrationStatus> integrations;

  const ContextSheet({
    super.key,
    required this.tasks,
    required this.kpis,
    required this.integrations,
  });

  static Future<void> show(
    BuildContext context, {
    required List<TaskItem> tasks,
    required List<KpiItem> kpis,
    required List<IntegrationStatus> integrations,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: JeonColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(top: 10),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: JeonColors.surface3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ContextSheet(tasks: tasks, kpis: kpis, integrations: integrations),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Progres Tugas'),
        ...tasks.map((t) => _taskRow(t)),
        const SizedBox(height: 6),
        const Divider(color: JeonColors.borderSoft, height: 24, indent: 16, endIndent: 16),
        _sectionTitle('Ringkasan Biaya'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: kpis.map((k) => _kpiCard(k)).toList(),
          ),
        ),
        const SizedBox(height: 10),
        const Divider(color: JeonColors.borderSoft, height: 24, indent: 16, endIndent: 16),
        _sectionTitle('Integrasi'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: integrations.map((i) => _integrationRow(i)).toList()),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w600,
            color: JeonColors.inkFaint,
          ),
        ),
      );

  Widget _taskRow(TaskItem t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: t.done ? JeonColors.accent : Colors.transparent,
                border: Border.all(color: t.done ? JeonColors.accent : JeonColors.border, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: t.done
                  ? const Icon(Icons.check, size: 11, color: Color(0xFF04150A))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.text,
                    style: TextStyle(
                      fontSize: 12.6,
                      color: t.done ? JeonColors.inkFaint : JeonColors.ink,
                      decoration: t.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(t.sub, style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _kpiCard(KpiItem k) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: JeonColors.surface2,
          border: Border.all(color: JeonColors.borderSoft),
          borderRadius: BorderRadius.circular(JeonRadius.small),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              k.value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: k.accent ? JeonColors.accent : JeonColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(k.label, style: const TextStyle(fontSize: 10.8, color: JeonColors.inkFaint)),
          ],
        ),
      );

  Widget _integrationRow(IntegrationStatus i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i.online ? JeonColors.accent : JeonColors.inkFaint,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(i.name, style: const TextStyle(fontSize: 12.4, color: JeonColors.ink))),
            Text(i.status, style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: JeonColors.inkFaint)),
          ],
        ),
      );
}
