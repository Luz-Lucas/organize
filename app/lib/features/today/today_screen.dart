import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/location_repository.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../domain/calendar_event.dart';
import '../../domain/event_tag.dart';
import '../../domain/home_presence.dart';
import '../../domain/ids.dart';
import '../../domain/note.dart';
import '../../domain/notice.dart';
import '../../domain/space.dart';
import '../../domain/system_notices.dart';
import '../../domain/task_item.dart';
import '../../domain/wake_override.dart';
import '../../domain/agenda.dart';
import '../../notebook/create_notebook.dart';
import '../../ui/common.dart';
import '../../ui/motif_painter.dart';
import '../../ui/org_theme.dart';
import '../agenda/event_dialog.dart';
import '../agenda/tag_style.dart';
import '../email/email_card.dart';
import '../tasks/task_dialog.dart';
import 'dashboard_cards.dart';
import 'dashboard_data.dart';
import 'notice_board.dart';
import 'notice_dialog.dart';
import 'wake_card.dart';

/// Largura útil (já descontada a barra lateral) a partir da qual o painel usa
/// duas colunas.
const double dashboardWideContent = 640;

/// Início: painel com o que importa de relance, em cartões compactos.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    // Ao entrar em Hoje, relê as manchetes (o provider pode seguir vivo na troca de tela).
    ref.invalidate(newsFeedProvider);
    _scheduleMidnightRollover();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  /// Agenda um Timer para a próxima meia-noite local, para que a data e as
  /// listas de "Hoje" atualizem mesmo sem nenhum stream emitir de novo
  /// (ex.: app deixado aberto durante a noite).
  void _scheduleMidnightRollover() {
    final now = ref.read(clockProvider)();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      if (!mounted) return;
      ref.invalidate(newsFeedProvider);
      setState(_scheduleMidnightRollover);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(newsFeedProvider);
    try {
      await ref.read(newsFeedProvider.future);
    } catch (_) {
      // O cartão de notícias mostra o erro; o gesto só precisa terminar.
    }
  }

  // --- Ações rápidas --------------------------------------------------------

  Future<void> _newTask() async {
    final spaces = ref.read(spacesProvider).value ?? const <Space>[];
    await showTaskEditor(
      context,
      task: TaskItem(id: newId(), title: ''),
      spaces: spaces,
      isNew: true,
    );
  }

  Future<void> _newEvent() async {
    final repo = ref.read(repositoryProvider);
    final spaces = ref.read(spacesProvider).value ?? const <Space>[];
    final now = ref.read(clockProvider)();
    final start = now.hour < 22
        ? DateTime(now.year, now.month, now.day, now.hour + 1)
        : DateTime(now.year, now.month, now.day + 1, 8);
    await showDialog<CalendarEvent>(
      context: context,
      builder: (_) => EventDialog(
        initialStart: start,
        initialEnd: start.add(const Duration(hours: 1)),
        spaces: spaces,
        tags: ref.read(eventTagsProvider).value ?? const <EventTag>[],
        onSave: (event) async {
          try {
            await repo.upsertEvent(event);
            return null;
          } on RepositoryException {
            return 'Não foi possível salvar o evento.';
          }
        },
      ),
    );
  }

  Future<void> _newNote() async {
    final all = ref.read(notesProvider).value ?? const <Note>[];
    final note = Note(id: newId(), title: _uniqueTitle('Sem título', all));
    try {
      await ref.read(repositoryProvider).upsertNote(note);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível criar a nota.');
      return;
    }
    if (mounted) context.push('/nota/${note.id}');
  }

  Future<void> _newNotebook() async {
    try {
      final note = await createNotebook(ref);
      if (mounted) context.push('/caderno/${note.id}');
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível criar o caderno.');
    }
  }

  String _uniqueTitle(String base, List<Note> all) {
    final taken = {for (final n in all) n.title};
    if (!taken.contains(base)) return base;
    var i = 2;
    while (taken.contains('$base $i')) {
      i++;
    }
    return '$base $i';
  }

  Future<void> _newNotice() => showDialog<void>(
        context: context,
        builder: (_) => const NoticeDialog(),
      );

  // --- Construção -----------------------------------------------------------

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Bom dia';
    if (now.hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  Widget _header(DateTime now) {
    final theme = Theme.of(context);
    final org = context.org;
    return MotifBackground(
      height: 96,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_greeting(now), style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now),
                    style: theme.textTheme.bodyLarge?.copyWith(color: org.accentText),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('open-news'),
              tooltip: 'Notícias',
              icon: const Icon(Icons.newspaper_outlined),
              onPressed: () => context.go('/noticias'),
            ),
            IconButton(
              key: const Key('open-home'),
              tooltip: 'Casa',
              icon: const Icon(Icons.home_outlined),
              onPressed: () => context.go('/casa'),
            ),
          ],
        ),
      ),
    );
  }

  /// Faixa de status: presença, ponte da Alexa e problemas de conexão.
  Widget? _statusStrip(
    DateTime now, {
    required bool connectionProblem,
    required BridgeStatus? bridge,
    required List<WakePlan> plans,
  }) {
    final chips = <Widget>[];
    final presence = presenceChip(
      settings: ref.watch(settingsProvider).value,
      last: ref.watch(lastLocationProvider).value,
      now: now,
    );
    if (presence != null) {
      final (icon, tone) = switch (presence.state) {
        PresenceState.home => (Icons.home_outlined, _ChipTone.good),
        PresenceState.away => (Icons.near_me_outlined, _ChipTone.neutral),
        _ => (Icons.location_off_outlined, _ChipTone.neutral),
      };
      chips.add(_StatusChip(
        key: const Key('status-presence'),
        icon: icon,
        label: presence.label,
        tone: tone,
        onTap: () => context.go('/ajustes'),
      ));
    }
    final banner = bridgeWarning(bridge, plans, now);
    if (banner != null) {
      final label = switch (bridgeHealth(bridge, now)) {
        BridgeHealth.offline => 'Alexa offline',
        BridgeHealth.authRequired => 'Login da Alexa expirou',
        BridgeHealth.error => 'Erro na ponte da Alexa',
        _ => 'Alexa não conectada',
      };
      chips.add(_StatusChip(
        key: const Key('status-bridge'),
        icon: Icons.cloud_off_outlined,
        label: label,
        semantics: banner,
        tone: _ChipTone.warn,
        onTap: () => context.go('/casa'),
      ));
    }
    if (connectionProblem) {
      chips.add(const _StatusChip(
        key: Key('status-connection'),
        icon: Icons.wifi_off_outlined,
        label: 'Sem conexão com o servidor',
        tone: _ChipTone.warn,
      ));
    }
    if (chips.isEmpty) return null;
    return Wrap(spacing: 8, children: chips);
  }

  Widget _quickActions() {
    return Row(
      children: [
        _QuickAction(
          key: const Key('quick-new-task'),
          icon: Icons.add_task,
          label: 'Tarefa',
          semantics: 'Nova tarefa',
          onTap: _newTask,
        ),
        const SizedBox(width: 8),
        _QuickAction(
          key: const Key('quick-new-event'),
          icon: Icons.event_available_outlined,
          label: 'Evento',
          semantics: 'Novo evento',
          onTap: _newEvent,
        ),
        const SizedBox(width: 8),
        _QuickAction(
          key: const Key('quick-new-note'),
          icon: Icons.note_add_outlined,
          label: 'Nota',
          semantics: 'Nova nota',
          onTap: _newNote,
        ),
        const SizedBox(width: 8),
        _QuickAction(
          key: const Key('quick-new-notebook'),
          icon: Icons.draw_outlined,
          label: 'Caderno',
          semantics: 'Novo caderno',
          onTap: _newNotebook,
        ),
        const SizedBox(width: 8),
        _QuickAction(
          key: const Key('quick-new-notice'),
          icon: Icons.campaign_outlined,
          label: 'Aviso',
          semantics: 'Novo aviso',
          onTap: _newNotice,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final events = ref.watch(eventsFromProvider(startOfDay(now)));
    final tasks = ref.watch(tasksProvider);
    final spaces = ref.watch(spacesProvider);
    final feed = ref.watch(newsFeedProvider);
    final bridge = ref.watch(bridgeStatusProvider).value;
    final plansAsync = ref.watch(wakePlansProvider);
    final plans = plansAsync.value ?? const <WakePlan>[];
    final userNotices = activeNotices(ref.watch(noticesProvider).value ?? const <Notice>[], now);
    final names = {for (final s in spaces.value ?? const <Space>[]) s.id: s.name};
    final taskList = tasks.value ?? const <TaskItem>[];
    final system = systemNotices(now: now, tasks: taskList, bridge: bridge, wakePlans: plans);
    final exam = events.value == null ? null : nextExam(now, events.value!);
    final strip = _statusStrip(
      now,
      connectionProblem: events.hasError || tasks.hasError,
      bridge: bridge,
      plans: plans,
    );

    final nowNext = NowNextCard(
      now: now,
      events: events,
      spaceNames: names,
      tags: tagMap(ref.watch(eventTagsProvider).value ?? const <EventTag>[]),
    );
    final wakeCard = WakeCard(
      now: now,
      plans: plansAsync,
      overrides: ref.watch(wakeOverridesProvider).value ?? const <WakeOverride>[],
    );
    final examCard = exam == null ? null : ExamCard(now: now, info: exam);
    final tasksCard = TasksCard(now: now, tasks: tasks, spaceNames: names);
    final board = NoticeBoard(system: system, notices: userNotices, now: now);
    const email = EmailCard();
    final news = NewsCard(now: now, feed: feed);

    const gap = SizedBox(height: 12);
    List<Widget> spaced(List<Widget?> items) => [
          for (final w in items.nonNulls) ...[w, gap],
        ];

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= dashboardWideContent;
          final top = <Widget>[
            _header(now),
            ?strip,
            _quickActions(),
          ];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
              key: const Key('dashboard-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...[
                        for (final w in top) ...[w, const SizedBox(height: 8)],
                      ],
                      const SizedBox(height: 4),
                      if (!wide)
                        ...spaced([nowNext, wakeCard, examCard, tasksCard, board, email, news])
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: spaced([nowNext, wakeCard, examCard, tasksCard]),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: spaced([board, email, news]),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

enum _ChipTone { good, neutral, warn }

/// Pílula da faixa de status; a área de toque tem no mínimo 48 dp de altura.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.tone,
    this.onTap,
    this.semantics,
  });

  final IconData icon;
  final String label;
  final _ChipTone tone;
  final VoidCallback? onTap;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    final (bg, fg) = switch (tone) {
      _ChipTone.good => (org.accentSoft, org.accentText),
      _ChipTone.neutral => (org.surfaceRaised, org.inkMuted),
      _ChipTone.warn => (theme.colorScheme.errorContainer, theme.colorScheme.onErrorContainer),
    };
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: org.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: semantics == null ? label : '$label. $semantics',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}

/// Botão compacto de criação (ícone + rótulo curto), com no mínimo 56 dp de altura.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.semantics,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = context.org;
    return Expanded(
      child: Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: Material(
          color: org.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(org.radiusMd),
            side: BorderSide(color: org.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 22, color: org.accentText),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
