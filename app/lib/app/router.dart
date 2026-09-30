import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/agenda/agenda_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/news/news_screen.dart';
import '../features/news/news_settings_screen.dart';
import '../features/notes/note_screen.dart';
import '../features/spaces/space_screen.dart';
import '../features/spaces/spaces_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/today/today_screen.dart';
import 'shell.dart';

/// Converte um Stream (ex.: mudanças de sessão) em Listenable para o go_router.
class StreamListenable extends ChangeNotifier {
  StreamListenable(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

GoRouter buildRouter({
  String initialLocation = '/',
  required bool Function() isSignedIn,
  Listenable? refresh,
}) =>
    GoRouter(
      initialLocation: initialLocation,
      refreshListenable: refresh,
      redirect: (context, state) {
        final atLogin = state.matchedLocation == '/login';
        if (!isSignedIn()) return atLogin ? null : '/login';
        if (atLogin) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
        ShellRoute(
          builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/', builder: (context, state) => const TodayScreen()),
            GoRoute(path: '/agenda', builder: (context, state) => const AgendaScreen()),
            GoRoute(path: '/tarefas', builder: (context, state) => const TasksScreen()),
            GoRoute(path: '/espacos', builder: (context, state) => const SpacesScreen()),
            GoRoute(
              path: '/espacos/:id',
              builder: (context, state) => SpaceScreen(spaceId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: '/nota/:id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoteScreen(key: ValueKey(id), noteId: id);
              },
            ),
            GoRoute(path: '/noticias', builder: (context, state) => const NewsScreen()),
            GoRoute(
              path: '/noticias/ajustes',
              builder: (context, state) => const NewsSettingsScreen(),
            ),
          ],
        ),
      ],
    );
