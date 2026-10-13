import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../domain/wake_override.dart';
import '../../ui/common.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';
import '../home/wake_next.dart';
import 'dashboard_cards.dart';
import 'dashboard_data.dart';

/// No máximo este tanto de despertares no painel; o resto está em Casa.
const wakeCardMax = 4;

enum _TomorrowChoice { time, skip, reset }

/// Um despertar já resolvido para exibição (próximo toque considerando as
/// exceções de data).
class _WakeRowData {
  const _WakeRowData(this.plan, this.next, this.tomorrow);

  final WakePlan plan;
  final DateTime? next;

  /// Exceção de amanhã, se houver.
  final WakeOverride? tomorrow;
}

/// Despertares ativos primeiro, pelo próximo toque; depois os sem próximo toque
/// e, por fim, os desligados (por horário).
List<_WakeRowData> _sorted(List<WakePlan> plans, List<WakeOverride> overrides, DateTime now) {
  final tomorrowKey = dateKey(DateTime(now.year, now.month, now.day + 1));
  final rows = [
    for (final p in plans)
      _WakeRowData(
        p,
        nextWake(p, overrides, now),
        overrides.where((o) => o.planId == p.id && o.dateKey == tomorrowKey).firstOrNull,
      ),
  ];
  int group(_WakeRowData r) => !r.plan.enabled ? 2 : (r.next == null ? 1 : 0);
  rows.sort((a, b) {
    final g = group(a).compareTo(group(b));
    if (g != 0) return g;
    if (group(a) == 0) return a.next!.compareTo(b.next!);
    return (a.plan.hour * 60 + a.plan.minute).compareTo(b.plan.hour * 60 + b.plan.minute);
  });
  return rows;
}

/// Cartão "Despertares" do painel: liga/desliga, próximo toque e o atalho
/// "Só amanhã" (pular ou mudar o horário apenas amanhã).
class WakeCard extends ConsumerStatefulWidget {
  const WakeCard({super.key, required this.now, required this.plans, required this.overrides});

  final DateTime now;
  final AsyncValue<List<WakePlan>> plans;
  final List<WakeOverride> overrides;

  @override
  ConsumerState<WakeCard> createState() => _WakeCardState();
}

class _WakeCardState extends ConsumerState<WakeCard> {
  Future<void> _toggle(WakePlan plan, bool enabled) async {
    try {
      await ref.read(alexaRepositoryProvider).upsertWakePlan(plan.copyWith(enabled: enabled));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível alterar o despertar.');
    }
  }

  Future<void> _tomorrow(_WakeRowData row) async {
    final now = ref.read(clockProvider)();
    final date = DateTime(now.year, now.month, now.day + 1);
    final plan = row.plan;
    final existing = row.tomorrow;
    final choice = await showModalBottomSheet<_TomorrowChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                '${plan.label} · amanhã (${DateFormat('EEE, d MMM', 'pt_BR').format(date)})',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              key: const Key('wake-tomorrow-time'),
              leading: const Icon(Icons.schedule),
              title: const Text('Mudar horário só amanhã'),
              onTap: () => Navigator.of(ctx).pop(_TomorrowChoice.time),
            ),
            ListTile(
              key: const Key('wake-tomorrow-skip'),
              leading: const Icon(Icons.alarm_off_outlined),
              title: const Text('Não tocar amanhã'),
              onTap: () => Navigator.of(ctx).pop(_TomorrowChoice.skip),
            ),
            if (existing != null)
              ListTile(
                key: const Key('wake-tomorrow-reset'),
                leading: const Icon(Icons.restore),
                title: const Text('Voltar ao normal'),
                onTap: () => Navigator.of(ctx).pop(_TomorrowChoice.reset),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final repo = ref.read(alexaRepositoryProvider);
    try {
      switch (choice) {
        case _TomorrowChoice.skip:
          await repo.setOverride(WakeOverride.skip(plan.id, date));
        case _TomorrowChoice.reset:
          await repo.clearOverride(plan.id, date);
        case _TomorrowChoice.time:
          final initial = existing != null && !existing.skip
              ? TimeOfDay(hour: existing.hour!, minute: existing.minute!)
              : TimeOfDay(hour: plan.hour, minute: plan.minute);
          final picked = await showTimePicker(context: context, initialTime: initial);
          if (!mounted || picked == null) return;
          await repo.setOverride(WakeOverride.at(plan.id, date, picked.hour, picked.minute));
      }
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível gravar a exceção.');
    }
  }

  String _timeLine(_WakeRowData row) {
    final p = row.plan;
    final t = row.tomorrow;
    return [
      '${twoDigits(p.hour)}:${twoDigits(p.minute)}',
      formatDays(p.days),
      if (t != null && !t.skip) 'amanhã ${twoDigits(t.hour!)}:${twoDigits(t.minute!)}',
    ].join(' · ');
  }

  /// "Toca amanhã às 06:30 · em 7 h 20 min", "Desligado" ou "Amanhã: pulado".
  String _status(_WakeRowData row) {
    if (!row.plan.enabled) return 'Desligado';
    final next = row.next;
    final skipTomorrow = row.tomorrow?.skip ?? false;
    if (next == null) return skipTomorrow ? 'Amanhã: pulado' : 'Sem próximo toque';
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final nextIsToday = DateTime(next.year, next.month, next.day) == today;
    if (skipTomorrow && !nextIsToday) return 'Amanhã: pulado';
    final text = 'Toca ${dayLabel(next, widget.now)} às ${hm(next)} · ${wakeCountdown(next, widget.now)}';
    return skipTomorrow ? '$text · amanhã pulado' : text;
  }

  Widget _row(_WakeRowData row) {
    final theme = Theme.of(context);
    final org = context.org;
    final plan = row.plan;
    final status = _status(row);
    final muted = !plan.enabled || status.startsWith('Amanhã: pulado');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: ValueKey('wake-row-${plan.id}'),
          borderRadius: BorderRadius.circular(org.radiusSm),
          onTap: () => context.push('/casa/despertar/${plan.id}'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.label, style: theme.textTheme.titleSmall),
                        Text(
                          _timeLine(row),
                          style: theme.textTheme.bodyMedium?.copyWith(color: org.inkMuted),
                        ),
                        Text(
                          status,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted ? org.inkMuted : org.accentText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'Despertar ${plan.label}',
                    child: Switch(
                      key: ValueKey('wake-toggle-${plan.id}'),
                      value: plan.enabled,
                      onChanged: (v) => _toggle(plan, v),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        TextButton.icon(
          key: ValueKey('wake-tomorrow-${plan.id}'),
          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => _tomorrow(row),
          icon: const Icon(Icons.event_busy_outlined, size: 18),
          label: Text('Só amanhã', semanticsLabel: 'Só amanhã: ${plan.label}'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final list = widget.plans.value;
    final rows = list == null ? const <_WakeRowData>[] : _sorted(list, widget.overrides, widget.now);
    final shown = rows.take(wakeCardMax).toList();
    return OrgCard(
      key: const Key('wake-card'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DashHeader(icon: Icons.alarm, title: 'Despertares'),
          if (list == null && widget.plans.hasError)
            const EmptyHint('Não foi possível carregar os despertares.')
          else if (list == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('Nenhum despertar', key: Key('wake-empty')),
            ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) Divider(height: 1, color: org.line),
            _row(shown[i]),
          ],
          if (list != null)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  key: const Key('wake-new'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => context.push('/casa/despertar/novo'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo despertar'),
                ),
                if (rows.length > wakeCardMax)
                  TextButton(
                    key: const Key('wake-all'),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () => context.go('/casa'),
                    child: Text('Ver todos (${rows.length})'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
