import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../domain/ids.dart';
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

enum _WakeMenu { edit, tomorrow, duplicate, delete }

/// Um despertar já resolvido para exibição (próximo toque considerando as
/// exceções de data).
class _WakeRowData {
  const _WakeRowData(this.plan, this.next, this.date, this.exception);

  final WakePlan plan;
  final DateTime? next;

  /// Dia do próximo toque (mesmo pulado): é o que o "Só …" edita.
  final DateTime date;

  /// Exceção desse dia, se houver.
  final WakeOverride? exception;
}

/// "hoje", "amanhã" ou "qua, 21 out": o dia do próximo toque, relativo a [now].
String _dayWord(DateTime date, DateTime now) => dayLabel(date, now);

String _capitalized(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Despertares ativos primeiro, pelo próximo toque; depois os sem próximo toque
/// e, por fim, os desligados (por horário).
List<_WakeRowData> _sorted(
  List<WakePlan> plans,
  List<WakeOverride> overrides,
  DateTime now,
) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  _WakeRowData row(WakePlan p) {
    // Sem nenhum dia escolhido, o "Só …" vale para amanhã (pode criar um toque extra).
    final date = nextOccurrenceDate(p, overrides, now) ?? tomorrow;
    final key = dateKey(date);
    return _WakeRowData(
      p,
      nextWake(p, overrides, now),
      date,
      overrides.where((o) => o.planId == p.id && o.dateKey == key).firstOrNull,
    );
  }

  final rows = [for (final p in plans) row(p)];
  int group(_WakeRowData r) => !r.plan.enabled ? 2 : (r.next == null ? 1 : 0);
  rows.sort((a, b) {
    final g = group(a).compareTo(group(b));
    if (g != 0) return g;
    if (group(a) == 0) return a.next!.compareTo(b.next!);
    return (a.plan.hour * 60 + a.plan.minute).compareTo(
      b.plan.hour * 60 + b.plan.minute,
    );
  });
  return rows;
}

/// Cartão "Despertares" do painel: liga/desliga, próximo toque e o atalho
/// "Só hoje/amanhã/…" (pular ou mudar o horário só no próximo toque).
class WakeCard extends ConsumerStatefulWidget {
  const WakeCard({
    super.key,
    required this.now,
    required this.plans,
    required this.overrides,
  });

  final DateTime now;
  final AsyncValue<List<WakePlan>> plans;
  final List<WakeOverride> overrides;

  @override
  ConsumerState<WakeCard> createState() => _WakeCardState();
}

class _WakeCardState extends ConsumerState<WakeCard> {
  Future<void> _toggle(WakePlan plan, bool enabled) async {
    try {
      await ref
          .read(alexaRepositoryProvider)
          .upsertWakePlan(plan.copyWith(enabled: enabled));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível alterar o despertar.');
    }
  }

  String _hhmm(int h, int m) => '${twoDigits(h)}:${twoDigits(m)}';

  /// Grava [updated] respeitando [validateWakePlan]; devolve se gravou.
  Future<bool> _save(WakePlan updated) async {
    final problem = validateWakePlan(updated);
    if (problem != null) {
      showError(context, problem);
      return false;
    }
    try {
      await ref.read(alexaRepositoryProvider).upsertWakePlan(updated);
      return true;
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível alterar o despertar.');
      return false;
    }
  }

  /// Muda o horário padrão do despertar. A exceção do próximo toque não é tocada.
  Future<void> _editTime(WakePlan plan) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: plan.hour, minute: plan.minute),
    );
    if (!mounted || picked == null) return;
    if (picked.hour == plan.hour && picked.minute == plan.minute) return;
    final saved = await _save(
      plan.copyWith(hour: picked.hour, minute: picked.minute),
    );
    if (!saved || !mounted) return;
    showUndo(
      messenger,
      'Despertar às ${_hhmm(picked.hour, picked.minute)}',
      () async {
        await ref.read(alexaRepositoryProvider).upsertWakePlan(plan);
      },
    );
  }

  /// Folha com chips Dom…Sáb; devolve os dias escolhidos (ordenados 1..7) ou null.
  Future<void> _editDays(WakePlan plan) async {
    final messenger = ScaffoldMessenger.of(context);
    final days = await showModalBottomSheet<List<int>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _DaysSheet(plan: plan),
    );
    if (!mounted || days == null) return;
    final saved = await _save(plan.copyWith(days: days));
    if (!saved || !mounted) return;
    showUndo(messenger, 'Dias alterados: ${formatDays(days)}', () async {
      await ref.read(alexaRepositoryProvider).upsertWakePlan(plan);
    });
  }

  Future<void> _duplicate(WakePlan plan) async {
    final messenger = ScaffoldMessenger.of(context);
    final copy = WakePlan.fromMap({
      ...plan.toMap(),
      'id': newId(),
      'label': '${plan.label} (cópia)',
      'enabled': false,
    });
    final problem = validateWakePlan(copy);
    if (problem != null) {
      showError(context, problem);
      return;
    }
    final repo = ref.read(alexaRepositoryProvider);
    try {
      await repo.upsertWakePlan(copy);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível duplicar o despertar.');
      return;
    }
    showUndo(
      messenger,
      'Despertar duplicado (desligado)',
      () => repo.deleteWakePlan(copy.id),
    );
  }

  Future<void> _delete(WakePlan plan) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir despertar?'),
        content: const Text(
          'O alarme reserva já agendado também será cancelado pela ponte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('wake-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    // A exclusão leva as exceções junto (cascata); guardo-as para o "Desfazer".
    final overrides = [
      for (final o in widget.overrides)
        if (o.planId == plan.id) o,
    ];
    final repo = ref.read(alexaRepositoryProvider);
    try {
      await repo.deleteWakePlan(plan.id);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível excluir o despertar.');
      return;
    }
    showUndo(messenger, 'Despertar excluído', () async {
      await repo.upsertWakePlan(plan);
      for (final o in overrides) {
        await repo.setOverride(o);
      }
    });
  }

  void _onMenu(_WakeMenu choice, _WakeRowData row) {
    switch (choice) {
      case _WakeMenu.edit:
        context.push('/casa/despertar/${row.plan.id}');
      case _WakeMenu.tomorrow:
        _tomorrow(row);
      case _WakeMenu.duplicate:
        _duplicate(row.plan);
      case _WakeMenu.delete:
        _delete(row.plan);
    }
  }

  Future<void> _tomorrow(_WakeRowData row) async {
    final now = ref.read(clockProvider)();
    final date = row.date;
    final word = _dayWord(date, now);
    final plan = row.plan;
    final existing = row.exception;
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
                '${plan.label} · $word (${DateFormat('EEE, d MMM', 'pt_BR').format(date)})',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              key: const Key('wake-tomorrow-time'),
              leading: const Icon(Icons.schedule),
              title: Text('Mudar horário só $word'),
              onTap: () => Navigator.of(ctx).pop(_TomorrowChoice.time),
            ),
            ListTile(
              key: const Key('wake-tomorrow-skip'),
              leading: const Icon(Icons.alarm_off_outlined),
              title: Text('Não tocar $word'),
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
          final picked = await showTimePicker(
            context: context,
            initialTime: initial,
          );
          if (!mounted || picked == null) return;
          await repo.setOverride(
            WakeOverride.at(plan.id, date, picked.hour, picked.minute),
          );
      }
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível gravar a exceção.');
    }
  }

  /// Horário e dias (cada um é um botão de 48 dp) e, se houver, o horário trocado do próximo toque.
  Widget _timeLine(_WakeRowData row) {
    final theme = Theme.of(context);
    final org = context.org;
    final p = row.plan;
    final t = row.exception;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: org.inkMuted);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InkWell(
          key: ValueKey('wake-time-${p.id}'),
          borderRadius: BorderRadius.circular(org.radiusSm),
          onTap: () => _editTime(p),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                widthFactor: 1,
                child: Semantics(
                  label: 'Mudar horário de ${p.label}',
                  excludeSemantics: true,
                  child: Text(
                    _hhmm(p.hour, p.minute),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: org.accentText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        InkWell(
          key: ValueKey('wake-days-${p.id}'),
          borderRadius: BorderRadius.circular(org.radiusSm),
          onTap: () => _editDays(p),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                widthFactor: 1,
                child: Semantics(
                  label: 'Mudar dias de ${p.label}',
                  excludeSemantics: true,
                  child: Text(formatDays(p.days), style: muted),
                ),
              ),
            ),
          ),
        ),
        if (t != null && !t.skip)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${_dayWord(row.date, widget.now)} ${_hhmm(t.hour!, t.minute!)}', style: muted),
          ),
      ],
    );
  }

  /// "Toca amanhã às 06:30 · em 7 h 20 min", "Desligado" ou "Hoje: pulado"
  /// (o próximo toque foi pulado).
  String _status(_WakeRowData row) {
    if (!row.plan.enabled) return 'Desligado';
    final next = row.next;
    if (row.exception?.skip ?? false) return '${_capitalized(_dayWord(row.date, widget.now))}: pulado';
    if (next == null) return 'Sem próximo toque';
    return 'Toca ${dayLabel(next, widget.now)} às ${hm(next)} · ${wakeCountdown(next, widget.now)}';
  }

  Widget _row(_WakeRowData row) {
    final theme = Theme.of(context);
    final org = context.org;
    final plan = row.plan;
    final status = _status(row);
    final word = _dayWord(row.date, widget.now);
    final muted = !plan.enabled || status.endsWith(': pulado');
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
                        _timeLine(row),
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
                  PopupMenuButton<_WakeMenu>(
                    key: ValueKey('wake-menu-${plan.id}'),
                    tooltip: 'Mais opções: ${plan.label}',
                    padding: const EdgeInsets.all(12),
                    onSelected: (c) => _onMenu(c, row),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        key: Key('wake-menu-edit'),
                        value: _WakeMenu.edit,
                        child: Text('Editar tudo…'),
                      ),
                      PopupMenuItem(
                        key: const Key('wake-menu-tomorrow'),
                        value: _WakeMenu.tomorrow,
                        child: Text('Só $word…'),
                      ),
                      const PopupMenuItem(
                        key: Key('wake-menu-duplicate'),
                        value: _WakeMenu.duplicate,
                        child: Text('Duplicar'),
                      ),
                      const PopupMenuItem(
                        key: Key('wake-menu-delete'),
                        value: _WakeMenu.delete,
                        child: Text('Excluir'),
                      ),
                    ],
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
          label: Text('Só $word', semanticsLabel: 'Só $word: ${plan.label}'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final list = widget.plans.value;
    final rows = list == null
        ? const <_WakeRowData>[]
        : _sorted(list, widget.overrides, widget.now);
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
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
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

/// Folha "Dias" do despertar: chips Dom…Sáb, Salvar e Cancelar.
class _DaysSheet extends StatefulWidget {
  const _DaysSheet({required this.plan});

  final WakePlan plan;

  @override
  State<_DaysSheet> createState() => _DaysSheetState();
}

class _DaysSheetState extends State<_DaysSheet> {
  late final Set<int> _days = {...widget.plan.days};
  bool _showError = false;

  void _save() {
    if (_days.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop((_days.toList()..sort()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.plan.label} · dias',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in daysSundayFirst)
                  FilterChip(
                    key: ValueKey('wake-days-chip-$d'),
                    label: Text(weekdayShort[d - 1]),
                    selected: _days.contains(d),
                    onSelected: (on) => setState(() {
                      on ? _days.add(d) : _days.remove(d);
                      _showError = false;
                    }),
                  ),
              ],
            ),
            if (_showError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Escolha pelo menos um dia',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('wake-days-cancel'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  key: const Key('wake-days-save'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _save,
                  child: const Text('Salvar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
