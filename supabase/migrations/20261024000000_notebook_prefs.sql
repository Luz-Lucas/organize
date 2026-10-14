-- Favoritos do Caderno (canetas e cores) e modo da barra, sincronizados entre aparelhos.
-- Formato: {"v":1,"pens":[{"tool":"pen","argb":...,"width":...}],"colors":[argb,...],"compact":true}
-- Objeto vazio = nunca personalizado (o app usa os favoritos padrão).
alter table public.user_settings
  add column notebook_prefs jsonb not null default '{}'::jsonb
    check (jsonb_typeof(notebook_prefs) = 'object');
