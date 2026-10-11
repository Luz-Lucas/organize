import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/notes/notes_tree.dart';
import '../ui/org_theme.dart';

typedef _Dest = ({String path, IconData icon, String label});

const _inicio = (path: '/', icon: Icons.space_dashboard_outlined, label: 'Início');
const _agenda = (path: '/agenda', icon: Icons.calendar_month_outlined, label: 'Agenda');
const _tarefas = (path: '/tarefas', icon: Icons.check_circle_outline, label: 'Tarefas');
const _notas = (path: '/notas', icon: Icons.description_outlined, label: 'Notas');
const _noticias = (path: '/noticias', icon: Icons.newspaper_outlined, label: 'Notícias');
const _casa = (path: '/casa', icon: Icons.cottage_outlined, label: 'Casa');
const _ajustes = (path: '/ajustes', icon: Icons.settings_outlined, label: 'Ajustes');
const _mais = (path: '/mais', icon: Icons.more_horiz, label: 'Mais');

const _sidebarItems = [_inicio, _agenda, _tarefas, _notas, _noticias, _casa, _ajustes];
const _bottomItems = [_inicio, _agenda, _tarefas, _notas, _mais];

/// Qual destino de [_sidebarItems] está ativo para [location] (ou null).
String? _activePath(String location) {
  if (location == '/') return '/';
  if (location.startsWith('/agenda')) return '/agenda';
  if (location.startsWith('/tarefas')) return '/tarefas';
  if (location.startsWith('/notas') ||
      location.startsWith('/nota/') ||
      location.startsWith('/espacos')) {
    return '/notas';
  }
  if (location.startsWith('/noticias')) return '/noticias';
  if (location.startsWith('/casa')) return '/casa';
  if (location.startsWith('/ajustes')) return '/ajustes';
  if (location.startsWith('/mais')) return '/mais';
  return null;
}

/// Casca do app: barra lateral recolhível (largura >= 720) ou barra inferior.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const double wideBreakpoint = 720;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _collapsed = false;

  String? get _noteId {
    final m = RegExp(r'^/nota/([^/]+)').firstMatch(widget.location);
    return m?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    final active = _activePath(widget.location);
    if (MediaQuery.sizeOf(context).width >= AppShell.wideBreakpoint) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              active: active,
              collapsed: _collapsed,
              noteId: _noteId,
              onToggle: () => setState(() => _collapsed = !_collapsed),
            ),
            Expanded(child: widget.child),
          ],
        ),
      );
    }
    // No celular, rotas de "Mais" (Notícias, Casa, Ajustes) acendem o item Mais.
    final moreActive = const {'/noticias', '/casa', '/ajustes', '/mais'}.contains(active);
    final index = moreActive ? 4 : _bottomItems.indexWhere((d) => d.path == active);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: context.org.line))),
        child: NavigationBar(
          selectedIndex: index < 0 ? 0 : index,
          // Fora dos destinos conhecidos nenhum item deve parecer selecionado,
          // mas NavigationBar exige um índice; usamos o primeiro.
          onDestinationSelected: (i) => context.go(_bottomItems[i].path),
          destinations: [
            for (final d in _bottomItems)
              NavigationDestination(
                key: ValueKey('nav-${d.path}'),
                icon: Icon(d.icon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.active,
    required this.collapsed,
    required this.noteId,
    required this.onToggle,
  });

  final String? active;
  final bool collapsed;
  final String? noteId;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final theme = Theme.of(context);
    return Material(
      color: org.surface,
      child: Container(
        width: collapsed ? 64 : 248,
        decoration: BoxDecoration(border: Border(right: BorderSide(color: org.line))),
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(collapsed ? 0 : 16, 16, collapsed ? 0 : 8, 8),
                child: collapsed
                    ? Column(
                        children: [
                          Text(org.glyph,
                              style: theme.textTheme.titleLarge?.copyWith(color: org.accentText)),
                          const SizedBox(height: 8),
                          _collapseButton(),
                        ],
                      )
                    : Row(
                        children: [
                          Text(org.glyph,
                              style: theme.textTheme.titleLarge?.copyWith(color: org.accentText)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Organizacional',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          _collapseButton(),
                        ],
                      ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final d in _sidebarItems) ...[
                        _NavItem(dest: d, active: active == d.path, collapsed: collapsed),
                        if (d.path == '/notas' && !collapsed) NotesTree(activeNoteId: noteId),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collapseButton() => IconButton(
        key: const Key('sidebar-collapse'),
        tooltip: collapsed ? 'Expandir barra lateral' : 'Recolher barra lateral',
        visualDensity: VisualDensity.compact,
        icon: Icon(collapsed ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left,
            size: 18),
        onPressed: onToggle,
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.dest, required this.active, required this.collapsed});

  final _Dest dest;
  final bool active;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final org = context.org;
    final fg = active ? org.accentText : org.inkMuted;
    final item = Material(
      color: active ? org.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(org.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('nav-${dest.path}'),
        onTap: () => context.go(dest.path),
        child: SizedBox(
          height: 38,
          child: collapsed
              ? Center(child: Icon(dest.icon, size: 20, color: fg))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(dest.icon, size: 18, color: fg),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          dest.label,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: active ? org.accentText : org.ink,
                                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: collapsed ? Tooltip(message: dest.label, child: item) : item,
    );
  }
}
