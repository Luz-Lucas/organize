import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../data/local_shopping_repository.dart';
import '../data/shopping_repository.dart';
import '../data/supabase_shopping_repository.dart';
import 'widget_background.dart';

/// Link do toque num item do widget Mercado: `organizacional://mercado/check?id=<id do item>`.
/// O Kotlin monta a mesma URI; ela vai para o segundo plano (não abre o app).
Uri shopCheckUri(String itemId) => Uri(
  scheme: 'organizacional',
  host: 'mercado',
  path: '/check',
  queryParameters: {'id': itemId},
);

/// Id do item de um [shopCheckUri]; qualquer outra URI (ou id vazio) -> `null`.
String? shopCheckIdFromUri(Uri? uri) {
  if (uri == null ||
      uri.scheme != 'organizacional' ||
      uri.host != 'mercado' ||
      uri.path != '/check') {
    return null;
  }
  final id = uri.queryParameters['id'];
  return (id == null || id.isEmpty) ? null : id;
}

/// Trata um toque vindo do widget: marca o item como comprado. Devolve `true` se gravou.
/// Sem sessão ([repository] nulo), sem rede ou URI estranha: não faz nada e não lança — o item
/// volta ao widget na próxima sincronização.
Future<bool> handleWidgetInteraction(
  Uri? uri,
  Future<ShoppingRepository?> Function() repository,
) async {
  final id = shopCheckIdFromUri(uri);
  if (id == null) return false;
  try {
    final repo = await repository();
    if (repo == null) return false;
    await repo.setChecked(id, true);
    return true;
  } catch (_) {
    return false;
  }
}

/// Chamado pelo `home_widget` num isolate sem interface (toque em item do Mercado).
@pragma('vm:entry-point')
Future<void> widgetInteractivityCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = await backgroundSupabaseClient();
  if (client == null || client.auth.currentSession == null) return;
  // Com o banco local da conta: marca nele (fila) e tenta enviar; sem ele, direto na nuvem como antes.
  final local = await openBackgroundLocal(client);
  if (local != null) {
    try {
      final ok = await handleWidgetInteraction(uri, () async => LocalFirstShoppingRepository(local.store));
      if (ok) await local.push();
      return;
    } finally {
      await local.close();
    }
  }
  await handleWidgetInteraction(uri, () async => SupabaseShoppingRepository(client));
}

/// Registra o callback acima (Android).
Future<void> registerWidgetInteractivity() async {
  await HomeWidget.registerInteractivityCallback(widgetInteractivityCallback);
}
