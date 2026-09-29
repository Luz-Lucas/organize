import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renderiza [value] com [builder]. Se o stream falhar (ex.: queda de rede)
/// mas já houver dados carregados, mantém os dados na tela e mostra um aviso
/// discreto em vez de substituir tudo pela tela de erro; a tela de erro cheia
/// só aparece quando ainda não há dados.
Widget asyncView<T>(AsyncValue<T> value, Widget Function(T data) builder) {
  final data = value.value;
  if (data != null) {
    final content = builder(data);
    if (!value.hasError) return content;
    return Column(
      children: [
        const _ConnectionNotice('Sem conexão com o servidor. Tentando de novo…'),
        Expanded(child: content),
      ],
    );
  }
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

class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, size: 18, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

void showError(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
