# Caderno com S Pen — Design

**Aprovado no chat (2026-10-13).** Objetivo: substituir o Samsung Notes por notas manuscritas do próprio Organizacional, editáveis e sincronizadas em celular, tablet e Linux, com as funções base do Samsung Notes e correção de escrita (endireitar, ortografia, converter em texto, gestos).

## Decisões do usuário
- Formato: **nota tipo Caderno** (página livre), separada das notas de texto (que não mudam).
- Correção de escrita: **as quatro** — endireitar a letra, corrigir ortografia, converter em texto, gestos de edição.

## Fases
1. **Caneta e caderno** (este plano): tipo de nota, páginas, S Pen, ferramentas, sincronização, Linux.
2. **Inteligência da escrita** (Android): reconhecimento pt-BR no aparelho (Google ML Kit Digital Ink, modelo baixado uma vez, grátis), converter em texto, busca por escrita, endireitar, ortografia (corretor do Android), gestos. Linux só mostra o texto já reconhecido.
3. **Extras**: reconhecimento de formas, anotar PDF (inclusive do Drive), exportar caderno em PDF.

## Modelo de dados
- `notes.kind text not null default 'text' check (kind in ('text','notebook'))`. Caderno usa `body = ''`.
- `note_pages(id uuid pk default gen_random_uuid(), user_id uuid not null default auth.uid() → auth.users on delete cascade, note_id uuid not null → notes(id) on delete cascade, idx int not null check (idx >= 0), background text not null default 'lined' check in ('blank','lined','grid','dots'), data text not null default '', recognized_text text not null default '', version int not null default 0, updated_at timestamptz not null default now(), unique (note_id, idx) deferrable initially deferred)` + RLS do dono + realtime; check de tamanho `octet_length(data) <= 4_000_000`.
- Imagens: bucket privado do Supabase Storage `notebook-images`, caminho `<user_id>/<note_id>/<uuid>.<ext>`, policies só do dono; limite 10 MB por imagem.
- **Documento da página** (`data`): JSON v1 compactado com gzip e codificado em base64:
  `{"v":1,"strokes":[{"id","tool":"fountain|pen|pencil|highlighter","color":"#RRGGBBAA","width":float,"pts":[x,y,p, ...]}],"texts":[{"id","x","y","w","text","size","color"}],"images":[{"id","x","y","w","h","path"}],"deleted":[ids]}`.
  Coordenadas em unidades de página (largura 1000; altura 1414, proporção A4), arredondadas a 0,1; pressão 0–1 em 2 casas.
- **Sincronização e conflito**: traços, textos e imagens são imutáveis com id (editar = apagar + criar novo id). Mesclar duas versões = união por id menos `deleted` (tombstones). Gravação otimista `update … where version = v` → se 0 linhas, relê, mescla e regrava. Salvamento automático 1,5 s após o último traço e ao sair.

## Fase 1 — comportamento
- Lista de notas: "Novo caderno" ao lado de "Nova nota"; ícone de caderno; abrir em `/caderno/:id`.
- Páginas A4 em rolagem vertical, "+ Página" no fim, fundo por página (em branco, pautado, quadriculado, pontilhado), apagar/duplicar página.
- Entrada: **caneta desenha; dedo rola e faz zoom** (palm rejection); chave "Desenhar com o dedo". Pressão → espessura (traço suave com `perfect_freehand` ou equivalente). Botão lateral da S Pen ou a ponta de borracha (inverted stylus) = borracha enquanto pressionado. Mouse no Linux desenha (botão esquerdo), roda/arrasto do meio rola.
- Barra: canetas (tinteiro, caneta, lápis, marca-texto translúcido), 10 cores do tema + seletor, 5 espessuras, borracha (por traço / parcial), laço (selecionar, mover, redimensionar, mudar cor, copiar, colar, apagar), texto (caixa de texto editável), imagem (galeria/arquivo → Storage), desfazer/refazer, zoom (pinça e botões, 50–400 %).
- Desempenho: o traço em andamento desenha numa camada própria; traços prontos ficam em cache (`Picture`/raster por página); meta 60 fps com 5.000 traços por página.
- Busca de notas inclui `recognized_text` (vazio na fase 1). Miniatura da 1ª página na lista.

## Fase 2 — inteligência (resumo, plano próprio)
Reconhecimento por linha/palavra (agrupamento por proximidade/baseline) → `recognized_text` por página (busca e MCP). Converter (página ou laço) em caixa de texto. Endireitar: por linha, regressão da baseline → rotacionar/transladar, normalizar altura de x e espaçamento. Ortografia: corretor do Android (`DefaultSpellCheckService`) sobre as palavras reconhecidas; sugestão ao tocar; aceitar troca os traços pela palavra em fonte manuscrita (mesma cor/tamanho) — **não** na caligrafia do usuário. Gestos: rabisco sobre palavra apaga; ∧ abre espaço e caixa para escrever; traço vertical entre letras separa; arco abaixo de duas palavras junta.

## Fora do escopo
Colaboração em tempo real com outras pessoas, gravação de voz, sincronizar com o Samsung Notes, caligrafia sintética.
