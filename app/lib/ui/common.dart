import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';

export 'org_widgets.dart' show EmptyHint, SectionHeader;

/// Renderiza [value] com [builder]. Se o stream falhar (ex.: queda de rede)
/// mas já houver dados carregados, mantém os dados na tela, SEM mudar a forma
/// da árvore (embrulhar o conteúdo faria o Flutter descartar o estado de
/// campos de texto, abas e chips a cada queda/volta do websocket). O aviso de
/// conexão é único e global, na casca do app (`SyncStatusHost`, um ícone discreto). A tela
/// de erro cheia só aparece quando ainda não há dados.
Widget asyncView<T>(AsyncValue<T> value, Widget Function(T data) builder) {
  final data = value.value;
  if (data != null) return builder(data);
  return value.when(
    data: builder,
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (_, _) => const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Não foi possível carregar. Tentando de novo…', textAlign: TextAlign.center),
      ),
    ),
  );
}

String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

void showError(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// Aviso com ação "Desfazer" (substitui o aviso anterior). [undo] pode lançar
/// [RepositoryException]; nesse caso mostra "Não foi possível desfazer.".
void showUndo(
  ScaffoldMessengerState? messenger,
  String message,
  FutureOr<void> Function() undo,
) {
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: 'Desfazer',
        onPressed: () async {
          try {
            await undo();
          } on RepositoryException {
            messenger.showSnackBar(const SnackBar(content: Text('Não foi possível desfazer.')));
          }
        },
      ),
    ));
}
