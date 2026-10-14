import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/widgets/widget_appearance.dart';
import 'package:organizacional/widgets/widget_sink.dart';
import 'package:organizacional/widgets/widget_sync.dart';

class MapSink implements WidgetSink {
  MapSink([Map<String, String>? initial]) : store = {...?initial};
  final Map<String, String> store;
  int refreshes = 0;
  bool failSave = false;
  @override
  Future<void> save(Map<String, String> data) async {
    if (failSave) throw Exception('falhou');
    store.addAll(data);
  }

  @override
  Future<void> refresh() async => refreshes++;
  @override
  Future<String?> read(String key) async => store[key];
}

ProviderContainer containerWith(WidgetSink sink) {
  final c = ProviderContainer(overrides: [widgetSinkProvider.overrideWithValue(sink)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('opções de transparência: 0, 25, 50, 75 e 90 %', () {
    expect(widgetBgTransparencyOptions, [0, 25, 50, 75, 90]);
  });

  test('widgetBgAlphaFor converte transparência em opacidade 0-255', () {
    expect(widgetBgAlphaFor(0), 255);
    expect(widgetBgAlphaFor(25), 191);
    expect(widgetBgAlphaFor(50), 128);
    expect(widgetBgAlphaFor(75), 64);
    expect(widgetBgAlphaFor(90), 26);
    expect(widgetBgAlphaFor(-10), 255);
    expect(widgetBgAlphaFor(150), 0);
  });

  test('padrão é 0 % quando nada foi gravado', () async {
    final c = containerWith(MapSink());
    expect(c.read(widgetBgTransparencyProvider), 0);
    await c.read(widgetBgTransparencyProvider.notifier).ready;
    expect(c.read(widgetBgTransparencyProvider), 0);
  });

  test('carrega a preferência gravada no aparelho', () async {
    final c = containerWith(MapSink({'w_bg_pct': '50'}));
    c.listen(widgetBgTransparencyProvider, (_, _) {});
    await c.read(widgetBgTransparencyProvider.notifier).ready;
    expect(c.read(widgetBgTransparencyProvider), 50);
  });

  test('valor gravado inválido é ignorado', () async {
    final c = containerWith(MapSink({'w_bg_pct': '33'}));
    c.listen(widgetBgTransparencyProvider, (_, _) {});
    await c.read(widgetBgTransparencyProvider.notifier).ready;
    expect(c.read(widgetBgTransparencyProvider), 0);
  });

  test('escolher grava w_bg_pct e w_bg_alpha e atualiza os widgets', () async {
    final sink = MapSink();
    final c = containerWith(sink);
    c.listen(widgetBgTransparencyProvider, (_, _) {});
    await c.read(widgetBgTransparencyProvider.notifier).set(75);
    expect(c.read(widgetBgTransparencyProvider), 75);
    expect(sink.store['w_bg_pct'], '75');
    expect(sink.store['w_bg_alpha'], '64');
    expect(sink.refreshes, 1);
  });

  test('escolher antes de a leitura terminar não é sobrescrito pela leitura', () async {
    final sink = MapSink({'w_bg_pct': '25'});
    final c = containerWith(sink);
    c.listen(widgetBgTransparencyProvider, (_, _) {});
    final n = c.read(widgetBgTransparencyProvider.notifier);
    await n.set(90);
    await n.ready;
    expect(c.read(widgetBgTransparencyProvider), 90);
  });

  test('falha ao gravar não derruba nem desfaz a escolha na tela', () async {
    final sink = MapSink()..failSave = true;
    final c = containerWith(sink);
    c.listen(widgetBgTransparencyProvider, (_, _) {});
    await c.read(widgetBgTransparencyProvider.notifier).set(50);
    expect(c.read(widgetBgTransparencyProvider), 50);
  });
}
