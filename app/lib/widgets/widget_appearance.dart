/// Porcentagens de transparência do fundo dos widgets oferecidas em Ajustes (padrão: 0).
const widgetBgTransparencyOptions = [0, 25, 50, 75, 90];

/// Chave (no armazenamento do `home_widget`) da porcentagem escolhida, para reabrir o app
/// com a opção marcada. É preferência do aparelho: cada celular tem um papel de parede.
const widgetBgPctKey = 'w_bg_pct';

/// Chave que o Kotlin lê: opacidade do fundo, 0 (invisível) a 255 (opaco).
const widgetBgAlphaKey = 'w_bg_alpha';

/// Transparência em % (0-100) -> opacidade 0-255 aplicada só ao fundo; o texto fica opaco.
int widgetBgAlphaFor(int transparencyPct) =>
    (255 * (100 - transparencyPct.clamp(0, 100)) / 100).round();
