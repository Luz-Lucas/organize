import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/drive_repository.dart';
import '../../data/file_picker_service.dart';
import '../../data/repository.dart';
import '../../domain/drive.dart';
import 'importer.dart';

/// Notas > "Importar arquivos": escolhe vários arquivos, mostra o progresso e o resumo no fim.
Future<void> runBatchImport(BuildContext context, WidgetRef ref) async {
  final picked = await ref.read(filePickerProvider).pickFiles();
  if (picked.isEmpty || !context.mounted) return;

  // Ninguém está observando o estado do Drive nesta tela: lê o primeiro valor direto do repositório.
  DriveState? driveState;
  try {
    driveState = await ref.read(driveRepositoryProvider).watchState().first.timeout(const Duration(seconds: 8));
  } catch (_) {
    driveState = null;
  }
  if (!context.mounted) return;
  final importer = Importer(
    repo: ref.read(repositoryProvider),
    drive: ref.read(driveRepositoryProvider),
    driveState: driveState,
  );
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = ValueNotifier<(int, int)>((0, picked.length));
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('import-progress'),
        title: const Text('Importando…'),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: p.$2 == 0 ? null : p.$1 / p.$2),
              const SizedBox(height: 8),
              Text('${p.$1} de ${p.$2}'),
            ],
          ),
        ),
      ),
    ),
  );

  ImportSummary summary;
  try {
    summary = await importer.importFiles(picked, onProgress: (d, t) => progress.value = (d, t));
  } on RepositoryException catch (e) {
    summary = ImportSummary()..errors.add(e.message);
  }
  navigator.pop(); // fecha o progresso
  progress.dispose();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('import-summary'),
      title: const Text('Importação concluída'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary.text),
            for (final e in summary.errors)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(e, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [FilledButton(key: const Key('import-summary-ok'), onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}
