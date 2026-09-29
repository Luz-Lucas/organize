import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _destinations = [
    (path: '/', icon: Icons.today_outlined, label: 'Hoje'),
    (path: '/agenda', icon: Icons.calendar_month_outlined, label: 'Agenda'),
    (path: '/tarefas', icon: Icons.check_circle_outline, label: 'Tarefas'),
    (path: '/espacos', icon: Icons.folder_outlined, label: 'Espaços'),
  ];

  int get _index {
    if (location.startsWith('/agenda')) return 1;
    if (location.startsWith('/tarefas')) return 2;
    if (location.startsWith('/espacos') || location.startsWith('/nota')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    void go(int i) => context.go(_destinations[i].path);
    if (MediaQuery.sizeOf(context).width >= 720) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: go,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}
