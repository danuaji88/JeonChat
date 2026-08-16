import 'package:flutter/material.dart';

import '../models/agent.dart';
import '../theme.dart';

class AgentDrawer extends StatelessWidget {
  final List<Agent> agents;

  const AgentDrawer({super.key, required this.agents});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: JeonColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [JeonColors.accent, JeonColors.accentDim],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text('J',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF04150A))),
                  ),
                  const SizedBox(width: 10),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: JeonColors.ink),
                      children: [
                        TextSpan(text: 'JeonChat '),
                        TextSpan(
                          text: 'Coworker',
                          style: TextStyle(color: JeonColors.inkFaint, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _navItem(Icons.chat_bubble_outline, 'Percakapan', active: true),
            _navItem(Icons.dashboard_outlined, 'Ruang Kerja'),
            _navItem(Icons.perm_media_outlined, 'Media & Konten'),
            _navItem(Icons.hub_outlined, 'Integrasi'),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'AGENT AKTIF',
                  style: TextStyle(fontSize: 10.5, letterSpacing: 1.0, color: JeonColors.inkFaint, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ...agents.map((a) => _agentCard(a)),
            const Spacer(),
            const Divider(color: JeonColors.borderSoft, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: JeonColors.surface3,
                      border: Border.all(color: JeonColors.border),
                    ),
                    alignment: Alignment.center,
                    child: const Text('AJ',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: JeonColors.inkMuted)),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Appa Jeon', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: JeonColors.ink)),
                      Text('Owner · Full Access', style: TextStyle(fontSize: 10.5, color: JeonColors.inkFaint)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, {bool active = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: active ? JeonColors.accentGlow : null,
        borderRadius: BorderRadius.circular(JeonRadius.small),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: active ? JeonColors.accent : JeonColors.inkMuted),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.2,
              color: active ? JeonColors.accent : JeonColors.inkMuted,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _agentCard(Agent agent) {
    final running = agent.status == AgentStatus.running;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: running ? JeonColors.accent : JeonColors.inkFaint,
              boxShadow: running
                  ? [BoxShadow(color: JeonColors.accentGlow, blurRadius: 0, spreadRadius: 3)]
                  : null,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(agent.name, style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w500, color: JeonColors.ink)),
                Text(
                  agent.task,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
