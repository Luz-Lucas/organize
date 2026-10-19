import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/agenda/agenda_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/fitness/fitness_screen.dart';
import '../features/github/github_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/wake_plan_screen.dart';
import '../features/more/more_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shopping/shopping_screen.dart';
import '../features/news/news_screen.dart';
import '../features/news/news_settings_screen.dart';
import '../features/notes/note_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/spaces/space_screen.dart';
import '../features/spaces/spaces_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/today/today_screen.dart';
import '../notebook/notebook_route.dart';
import '../notebook/pdf/pdf_reader_screen.dart';
import '../notebook/pdf/pick_pdf.dart';
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
        // Caderno: tela cheia, fora da casca (sem barras), para escrever com a caneta.
        GoRoute(
          path: '/caderno/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            final pdf = state.extra is PickedPdf ? state.extra! as PickedPdf : null;
            return NotebookRoute(key: ValueKey('caderno-$id'), noteId: id, initialPdf: pdf);
          },
        ),
        // O PDF original de um caderno, para ler e selecionar texto (aberto de dentro do caderno).
        GoRoute(
          path: '/caderno-pdf/:id',
          builder: (context, state) => PdfReaderScreen(noteId: state.pathParameters['id']!),
        ),
        // A nota vinculada a um caderno, aberta de dentro dele (caderno ou leitor de PDF): também em
        // tela cheia. Empurrar /nota/:id (dentro da casca) por cima de uma rota de tela cheia que já
        // está sobre a casca duplicaria a página da casca no navegador (tela vazia no release).
        GoRoute(
          path: '/caderno-nota/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return NoteScreen(key: ValueKey('caderno-nota-$id'), noteId: id);
          },
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/', builder: (context, state) => const TodayScreen()),
            GoRoute(path: '/agenda', builder: (context, state) => const AgendaScreen()),
            GoRoute(path: '/tarefas', builder: (context, state) => const TasksScreen()),
            GoRoute(path: '/notas', builder: (context, state) => const NotesScreen()),
            GoRoute(path: '/academia', builder: (context, state) => const FitnessScreen()),
            GoRoute(path: '/compras', builder: (context, state) => const ShoppingScreen()),
            GoRoute(path: '/mais', builder: (context, state) => const MoreScreen()),
            GoRoute(path: '/ajustes', builder: (context, state) => const SettingsScreen()),
            GoRoute(path: '/documentos', builder: (context, state) => const DocumentsScreen()),
            GoRoute(path: '/github', builder: (context, state) => const GithubScreen()),
            GoRoute(path: '/espacos', builder: (context, state) => const SpacesScreen()),
            GoRoute(
              path: '/espacos/:id',
              builder: (context, state) => SpaceScreen(spaceId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: '/nota/:id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoteOrNotebookRoute(key: ValueKey(id), noteId: id);
              },
            ),
            GoRoute(
              path: '/noticias',
              builder: (context, state) => const NewsScreen(),
              routes: [
                GoRoute(
                  path: 'ajustes',
                  builder: (context, state) => const NewsSettingsScreen(),
                ),
              ],
            ),
            GoRoute(path: '/casa', builder: (context, state) => const HomeScreen()),
            GoRoute(
              path: '/casa/despertar/:id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return WakePlanScreen(key: ValueKey('wake-$id'), planId: id);
              },
            ),
          ],
        ),
      ],
    );
