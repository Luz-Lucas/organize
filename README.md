# Organizacional

Agenda, tarefas, matérias, trabalhos e hobbies num só lugar. Flutter (Linux/Windows/Android) + Supabase.

## Estrutura
- `supabase/`: migrations SQL e testes pgTAP (`npx supabase test db`)
- `app/`: app Flutter (`lib/domain` regras puras, `lib/data` repositórios, `lib/features` telas)
- `docs/superpowers/`: spec e planos por fase

## Desenvolvimento local
```bash
npx supabase start                 # precisa do Docker
npx supabase status                # URL e chave anon → app/env.json (modelo: app/env.example.json)
cd app
TZ=America/Sao_Paulo flutter test --exclude-tags integration
flutter run -d linux --dart-define-from-file=env.json
```
Usuário local: Studio em http://127.0.0.1:54323 → Authentication → Add user.
No emulador Android, use `http://10.0.2.2:54321` como SUPABASE_URL.

## Nuvem (Supabase)
Para publicar o schema num projeto Supabase de verdade (não o local do Docker):
```bash
npx supabase login
npx supabase link --project-ref <ref-do-projeto>
npx supabase db push
```
Depois, crie o usuário pelo Dashboard (Authentication → Add user) — o app não
tem tela de cadastro.

**Importante:** logo após publicar, desabilite o cadastro público em
Authentication → Sign In / Providers → "Allow new users to sign up". O
`enable_signup = true` em `supabase/config.toml` vale só para o ambiente local
(Docker) e não deve ser levado para a nuvem com `supabase config push` — nesse
projeto o cadastro é sempre feito manualmente pelo Dashboard.

## Testes de integração (Supabase local)
```bash
eval "$(npx supabase status -o env)"
cd app && SUPABASE_URL="$API_URL" SUPABASE_ANON_KEY="$ANON_KEY" flutter test --tags integration
```

## Builds
```bash
cd app
flutter build linux --release --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

## Próximas fases
Veja `docs/superpowers/specs/2026-09-28-organizacional-design.md`: Claude via MCP, Google Agenda, GitHub, anexos (YouTube/PDF/docx).
