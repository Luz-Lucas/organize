import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notebook/intelligence/model_manager.dart';
import '../../notebook/state/handwriting_providers.dart';
import '../../ui/org_theme.dart';
import '../../ui/org_widgets.dart';

/// Ajustes > "Escrita à mão": o modelo de português do reconhecimento (baixar só no
/// Wi-Fi, com progresso, e apagar) e as chaves deste aparelho: reconhecer escrita
/// (busca), corretor ortográfico e gestos de edição.
class HandwritingCard extends ConsumerWidget {
  const HandwritingCard({super.key});

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final manager = ref.read(inkModelManagerProvider.notifier);
    final outcome = await manager.download();
    if (outcome != InkDownloadOutcome.needsWifi || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Você está sem Wi-Fi'),
        content: const Text(
          'O modelo de português tem cerca de 20 MB. Baixar agora gasta dados móveis. '
          'Você pode esperar para baixar no Wi-Fi.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('hw-mobile-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Baixar com dados móveis'),
          ),
        ],
      ),
    );
    if (ok == true) await manager.download(allowMobileData: true);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar o modelo?'),
        content: const Text(
          'Libera cerca de 20 MB. O reconhecimento da escrita para até você baixar o modelo de novo. '
          'O texto já reconhecido continua nas buscas.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('hw-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok == true) await ref.read(inkModelManagerProvider.notifier).delete();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final org = context.org;
    final prefs = ref.watch(handwritingPrefsProvider);
    final notifier = ref.read(handwritingPrefsProvider.notifier);
    final model = ref.watch(inkModelManagerProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(color: org.inkMuted);
    return OrgCard(
      key: const Key('handwriting-card'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('hw-recognize'),
            title: const Text('Reconhecer escrita (busca)'),
            subtitle: Text('Transforma o que você escreve nos cadernos em texto, só para buscar e copiar.', style: muted),
            value: prefs.recognize,
            onChanged: notifier.setRecognize,
          ),
          SwitchListTile(
            key: const Key('hw-spell'),
            title: const Text('Corretor ortográfico'),
            subtitle: Text('Sublinha palavras escritas com erro e sugere a correção.', style: muted),
            value: prefs.spellCheck,
            onChanged: notifier.setSpellCheck,
          ),
          SwitchListTile(
            key: const Key('hw-gestures'),
            title: const Text('Gestos de edição'),
            subtitle: Text('Rabisco apaga a palavra; ∧ abre espaço; traço vertical separa; arco junta.', style: muted),
            value: prefs.gestures,
            onChanged: notifier.setGestures,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _ModelSection(
              state: model,
              onDownload: () => _download(context, ref),
              onDelete: () => _delete(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelSection extends StatelessWidget {
  const _ModelSection({required this.state, required this.onDownload, required this.onDelete});

  final InkModelState state;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: context.org.inkMuted);
    if (state.status == InkModelStatus.unsupported) {
      return Text(
        'O reconhecimento da escrita funciona no Android. Neste aparelho a busca usa o texto reconhecido no celular.',
        key: const Key('hw-unsupported'),
        style: muted,
      );
    }
    final (label, detail) = switch (state.status) {
      InkModelStatus.checking => ('Verificando…', null),
      InkModelStatus.missing => ('Não instalado', 'Baixar só no Wi-Fi (cerca de 20 MB).'),
      InkModelStatus.downloading => ('Baixando…', null),
      InkModelStatus.ready => ('Instalado', 'Funciona sem internet.'),
      InkModelStatus.error => ('Não instalado', null),
      InkModelStatus.unsupported => ('', null),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Modelo de português (reconhecimento)', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(label, key: const Key('hw-model-status'), style: theme.textTheme.bodyMedium),
        if (detail != null) Text(detail, style: muted),
        if (state.status == InkModelStatus.downloading) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: state.progress),
        ],
        if (state.status == InkModelStatus.error && state.error != null) ...[
          const SizedBox(height: 4),
          Text(state.error!, key: const Key('hw-model-error'), style: muted?.copyWith(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 8),
        if (state.status == InkModelStatus.ready)
          OutlinedButton(key: const Key('hw-model-delete'), onPressed: onDelete, child: const Text('Apagar modelo'))
        else
          OutlinedButton(
            key: const Key('hw-model-download'),
            onPressed: state.status == InkModelStatus.downloading || state.status == InkModelStatus.checking ? null : onDownload,
            child: Text(state.status == InkModelStatus.error ? 'Tentar de novo' : 'Baixar modelo'),
          ),
      ],
    );
  }
}
