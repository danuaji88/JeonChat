enum AgentStatus { running, idle }

class Agent {
  final String name;
  final String task;
  final AgentStatus status;

  const Agent({required this.name, required this.task, required this.status});
}

class TaskItem {
  final String text;
  final String sub;
  final bool done;

  const TaskItem({required this.text, required this.sub, required this.done});
}

class IntegrationStatus {
  final String name;
  final String status;
  final bool online;

  const IntegrationStatus({
    required this.name,
    required this.status,
    required this.online,
  });
}

class KpiItem {
  final String value;
  final String label;
  final bool accent;

  const KpiItem({required this.value, required this.label, this.accent = false});
}
