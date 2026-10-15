#!/usr/bin/env bash
# Publica uma versão do Organize para o botão "Atualizar" de dentro do app.
#
#   tool/release.sh "<novidades em pt-BR>" [--windows] [--minor] [--dry-run]
#
#   --windows   também gera o app de Windows (tag windows-v<build> -> GitHub Actions -> baixa o zip)
#   --minor     sobe o Y de X.Y.Z (e zera o Z); sem isto sobe o Z. O build (+N) sempre sobe 1
#   --dry-run   faz tudo menos upload, commit, tag, a cópia final e a mexida no app instalado;
#               não toca no pubspec (a versão é passada ao Flutter por --build-name/--build-number)
#
# Rodar nesta máquina Linux (nunca no Windows). Passos:
#   1. calcula a nova versão a partir de app/pubspec.yaml (X.Y.Z+N)
#   2. compila o APK (arm64, ofuscado) e o bundle do Linux (.tar.gz)
#   3. commita só a linha `version:` do pubspec ("release vX.Y.Z+N")
#   4. com --windows: cria/envia a tag, espera o workflow e baixa o zip
#   5. calcula sha256 e tamanho, envia ao bucket privado app-releases (API REST + service role)
#   6. registra a linha em app_releases e apaga o que passar das 3 mais novas por plataforma
#   7. copia o APK para ~/organizacional-builds/organizacional.apk e atualiza ~/.local/opt/organizacional
#
# A chave service_role vem de `npx supabase projects api-keys`, fica só numa variável deste processo e nunca
# é impressa nem gravada em arquivo (vai ao curl por stdin, para nem aparecer na lista de processos).
set -euo pipefail

PROJECT_REF="dgarojxettnppcahedvk"
BUCKET="app-releases"
KEEP=3
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$REPO/app"
PUBSPEC="$APP/pubspec.yaml"
OUT_BASE="$HOME/organizacional-builds"
LOCAL_APP_DIR="$HOME/.local/opt/organizacional"

export JAVA_HOME="${JAVA_HOME:-$HOME/development/android-studio/jbr}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$HOME/development/flutter/bin:$PATH"

die() { echo "erro: $*" >&2; exit 1; }
say() { echo "==> $*"; }

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# ---------------------------------------------------------------- argumentos
NOTES=""
WITH_WINDOWS=0
MINOR=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --windows) WITH_WINDOWS=1 ;;
    --minor) MINOR=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage 0 ;;
    --*) die "opção desconhecida: $arg (veja --help)" ;;
    *) [[ -z "$NOTES" ]] || die "novidades dadas duas vezes (use aspas): '$NOTES' e '$arg'"; NOTES="$arg" ;;
  esac
done
[[ -n "${NOTES// /}" ]] || { echo "erro: faltou o texto das novidades." >&2; usage 1; }

for tool in python3 curl tar sha256sum stat flutter git; do
  command -v "$tool" >/dev/null || die "falta o programa '$tool'"
done
if [[ $DRY -eq 0 ]]; then
  for tool in npx rsync; do command -v "$tool" >/dev/null || die "falta o programa '$tool'"; done
fi
if [[ $WITH_WINDOWS -eq 1 && $DRY -eq 0 ]]; then command -v gh >/dev/null || die "falta o programa 'gh' (necessário com --windows)"; fi
[[ -f "$APP/env.json" ]] || die "falta app/env.json (veja app/env.example.json)"
[[ -x "$JAVA_HOME/bin/java" ]] || die "JAVA_HOME inválido: $JAVA_HOME"
[[ -d "$ANDROID_HOME" ]] || die "ANDROID_HOME inválido: $ANDROID_HOME"

# ---------------------------------------------------------------- versão
CURRENT="$(sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*+[0-9]*\)[[:space:]]*$/\1/p' "$PUBSPEC" | head -n1)"
[[ -n "$CURRENT" ]] || die "não achei 'version: X.Y.Z+N' em $PUBSPEC"
CUR_NAME="${CURRENT%%+*}"
CUR_BUILD="${CURRENT##*+}"
IFS=. read -r MAJ MIN PAT <<<"$CUR_NAME"
if [[ $MINOR -eq 1 ]]; then MIN=$((MIN + 1)); PAT=0; else PAT=$((PAT + 1)); fi
BUILD=$((CUR_BUILD + 1))
NAME="$MAJ.$MIN.$PAT"
TAG_LABEL="v$NAME+$BUILD"
# O versionCode do APK por ABI é 1000*ABI + build: acima de 999 o app não consegue mais separar os dois.
[[ $BUILD -lt 1000 ]] || die "o build chegou a $BUILD; o app só entende builds abaixo de 1000 (ver InstalledVersion.fromPackageInfo)"

if [[ $DRY -eq 0 ]]; then
  git -C "$REPO" diff --cached --quiet || die "há mudanças no índice do git (staged); o release só commita o pubspec. Limpe com 'git restore --staged .' e tente de novo"
  head_version="$(git -C "$REPO" show HEAD:app/pubspec.yaml | sed -n 's/^version:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' | head -n1)"
  [[ "$head_version" == "$CURRENT" ]] || die "a versão do pubspec ($CURRENT) não está commitada (HEAD tem '$head_version')"
  if [[ $WITH_WINDOWS -eq 1 ]]; then
    if git -C "$REPO" rev-parse -q --verify "refs/tags/windows-v$BUILD" >/dev/null; then
      die "a tag windows-v$BUILD já existe (sobra de um build antigo do Windows). Apague-a com 'git tag -d windows-v$BUILD && git push origin :refs/tags/windows-v$BUILD' ou publique sem --windows"
    fi
    if [[ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]]; then
      echo "aviso: há mudanças não commitadas; o app de Windows é compilado do que está COMMITADO (não inclui elas)." >&2
    fi
  fi
fi

say "Release $TAG_LABEL  (atual: $CURRENT)"
[[ $DRY -eq 1 ]] && say "MODO --dry-run: sem upload, commit, tag, nem alterar o app instalado"
echo "    novidades: $NOTES"

RELEASE_DIR="$OUT_BASE/releases/$NAME-b$BUILD"
mkdir -p "$RELEASE_DIR" "$OUT_BASE/symbols"

# ---------------------------------------------------------------- compilação
cd "$APP"
VERSION_FLAGS=(--build-name "$NAME" --build-number "$BUILD")

say "Compilando o APK (arm64, release, ofuscado)"
flutter build apk --release --split-per-abi --target-platform android-arm64 \
  --obfuscate --split-debug-info="$OUT_BASE/symbols" \
  --dart-define-from-file=env.json "${VERSION_FLAGS[@]}"
APK_SRC="$APP/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
[[ -f "$APK_SRC" ]] || die "o APK não foi gerado em $APK_SRC"
APK="$RELEASE_DIR/organizacional-$NAME-b$BUILD.apk"
cp "$APK_SRC" "$APK"

say "Compilando o app Linux (release)"
flutter build linux --release --dart-define-from-file=env.json "${VERSION_FLAGS[@]}"
BUNDLE="$APP/build/linux/x64/release/bundle"
[[ -x "$BUNDLE/organizacional" ]] || die "o bundle do Linux não foi gerado em $BUNDLE"
LINUX_PKG="$RELEASE_DIR/organizacional-linux-$NAME-b$BUILD.tar.gz"
tar -czf "$LINUX_PKG" -C "$BUNDLE" .

# ---------------------------------------------------------------- commit (só a linha version do pubspec)
if [[ $DRY -eq 0 ]]; then
  say "Commitando a versão no pubspec (só a linha version:)"
  tmp_pub="$(mktemp)"
  git -C "$REPO" show HEAD:app/pubspec.yaml | sed "s/^version:.*/version: $NAME+$BUILD/" >"$tmp_pub"
  blob="$(git -C "$REPO" hash-object -w "$tmp_pub")"
  rm -f "$tmp_pub"
  # Índice com a nova versão sobre o HEAD; o arquivo de trabalho só troca a linha (mudanças de outros ficam intactas).
  git -C "$REPO" update-index --cacheinfo "100644,$blob,app/pubspec.yaml"
  sed -i "s/^version:.*/version: $NAME+$BUILD/" "$PUBSPEC"
  git -C "$REPO" commit -q -m "release $TAG_LABEL"
  git -C "$REPO" log -1 --oneline
fi

# ---------------------------------------------------------------- Windows (GitHub Actions)
WINDOWS_PKG=""
if [[ $WITH_WINDOWS -eq 1 ]]; then
  if [[ $DRY -eq 1 ]]; then
    say "(dry-run) com --windows criaria e enviaria a tag windows-v$BUILD e baixaria o zip do workflow"
  else
    say "Windows: tag windows-v$BUILD -> GitHub Actions"
    sha_head="$(git -C "$REPO" rev-parse HEAD)"
    git -C "$REPO" tag "windows-v$BUILD"
    git -C "$REPO" push origin "windows-v$BUILD"
    run_id=""
    for _ in $(seq 1 30); do
      run_id="$(gh run list --workflow windows.yml --json databaseId,headSha --limit 20 \
        --jq "[.[] | select(.headSha == \"$sha_head\")][0].databaseId // empty" 2>/dev/null || true)"
      [[ -n "$run_id" ]] && break
      sleep 5
    done
    [[ -n "$run_id" ]] || die "o workflow do Windows não apareceu (veja 'gh run list --workflow windows.yml')"
    gh run watch "$run_id" --exit-status || die "o build do Windows falhou (gh run view $run_id --log-failed)"
    win_dir="$RELEASE_DIR/windows-artifact"
    rm -rf "$win_dir"
    gh run download "$run_id" -n Organize-windows -D "$win_dir"
    WINDOWS_PKG="$RELEASE_DIR/organizacional-windows-$NAME-b$BUILD.zip"
    cp "$(find "$win_dir" -name 'Organize-windows-*.zip' | head -n1)" "$WINDOWS_PKG"
    [[ -s "$WINDOWS_PKG" ]] || die "não achei o zip do Windows no artefato"
  fi
fi

# ---------------------------------------------------------------- sha256 e tamanho
PLATFORMS=(); FILES=(); SHAS=(); SIZES=(); PATHS=()
add_pkg() { # plataforma arquivo
  local sum size
  sum="$(sha256sum "$2" | cut -d' ' -f1)"
  size="$(stat -c %s "$2")"
  PLATFORMS+=("$1"); FILES+=("$2"); SHAS+=("$sum"); SIZES+=("$size"); PATHS+=("$1/$BUILD/$(basename "$2")")
}
add_pkg android "$APK"
add_pkg linux "$LINUX_PKG"
[[ -n "$WINDOWS_PKG" ]] && add_pkg windows "$WINDOWS_PKG"

say "Pacotes"
for i in "${!PLATFORMS[@]}"; do
  printf '    %-8s %s\n             %s bytes  sha256 %s\n' "${PLATFORMS[$i]}" "${PATHS[$i]}" "${SIZES[$i]}" "${SHAS[$i]}"
  if [[ ${SIZES[$i]} -gt 52428800 ]]; then
    echo "    aviso: passa de 50 MB; o plano gratuito do Supabase limita cada arquivo a 50 MB (Storage > Settings)." >&2
  fi
done

if [[ $DRY -eq 1 ]]; then
  say "(dry-run) pararia aqui: sem upload, sem registro em app_releases, sem limpeza, sem copiar o APK nem atualizar o app Linux"
  say "Arquivos em $RELEASE_DIR"
  exit 0
fi

# ---------------------------------------------------------------- Supabase (service role, só em memória)
SUPABASE_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["SUPABASE_URL"].rstrip("/"))' "$APP/env.json")"
case "$SUPABASE_URL" in
  http://127.0.0.1*|http://localhost*) die "app/env.json aponta para o Supabase local ($SUPABASE_URL); o release vai para a nuvem. Use o env.json de produção." ;;
esac

say "Obtendo a chave de serviço (não será exibida)"
SERVICE_KEY="$(npx --yes supabase projects api-keys --project-ref "$PROJECT_REF" -o json 2>/dev/null | python3 -c '
import json, sys
keys = json.load(sys.stdin)
pick = None
for k in keys:
    if k.get("name") == "service_role" and k.get("api_key"):
        pick = k["api_key"]
if pick is None:
    for k in keys:
        if str(k.get("api_key", "")).startswith("sb_secret_"):
            pick = k["api_key"]
            break
if pick is None:
    sys.exit(1)
sys.stdout.write(pick)
')" || die "não consegui a chave service_role (npx supabase login?)"
trap 'unset SERVICE_KEY' EXIT

# curl com a chave por stdin (config), nunca em argumento de linha de comando.
api() {
  {
    printf 'header = "apikey: %s"\n' "$SERVICE_KEY"
    [[ "$SERVICE_KEY" == eyJ* ]] && printf 'header = "Authorization: Bearer %s"\n' "$SERVICE_KEY"
    true
  } | curl -K - --silent --show-error --fail-with-body "$@"
}

say "Enviando ao bucket $BUCKET"
for i in "${!PLATFORMS[@]}"; do
  echo "    ${PATHS[$i]}"
  api -X POST "$SUPABASE_URL/storage/v1/object/$BUCKET/${PATHS[$i]}" \
    -H "Content-Type: application/octet-stream" -H "x-upsert: true" \
    --data-binary "@${FILES[$i]}" >/dev/null
done

say "Registrando em app_releases"
for i in "${!PLATFORMS[@]}"; do
  body="$(P="${PLATFORMS[$i]}" V="$NAME" B="$BUILD" S="${PATHS[$i]}" H="${SHAS[$i]}" Z="${SIZES[$i]}" N="$NOTES" python3 -c '
import json, os
print(json.dumps({
    "platform": os.environ["P"], "version": os.environ["V"], "build": int(os.environ["B"]),
    "storage_path": os.environ["S"], "sha256": os.environ["H"], "size_bytes": int(os.environ["Z"]),
    "notes": os.environ["N"],
}))')"
  api -X POST "$SUPABASE_URL/rest/v1/app_releases?on_conflict=platform,build" \
    -H "Content-Type: application/json" -H "Prefer: resolution=merge-duplicates,return=minimal" \
    --data "$body" >/dev/null
done

say "Limpando: mantém as $KEEP mais novas por plataforma"
for p in android linux windows; do
  old="$(api "$SUPABASE_URL/rest/v1/app_releases?platform=eq.$p&select=id,storage_path&order=build.desc&offset=$KEEP")"
  count="$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' <<<"$old")"
  [[ "$count" -gt 0 ]] || continue
  echo "    $p: removendo $count antiga(s)"
  prefixes="$(python3 -c 'import json,sys; print(json.dumps({"prefixes":[r["storage_path"] for r in json.load(sys.stdin)]}))' <<<"$old")"
  ids="$(python3 -c 'import json,sys; print(",".join(r["id"] for r in json.load(sys.stdin)))' <<<"$old")"
  api -X DELETE "$SUPABASE_URL/storage/v1/object/$BUCKET" -H "Content-Type: application/json" --data "$prefixes" >/dev/null
  api -X DELETE "$SUPABASE_URL/rest/v1/app_releases?id=in.($ids)" >/dev/null
done
unset SERVICE_KEY

# ---------------------------------------------------------------- saída local
say "Copiando o APK para $OUT_BASE/organizacional.apk"
cp "$APK" "$OUT_BASE/organizacional.apk"
say "Atualizando o app Linux local em $LOCAL_APP_DIR"
mkdir -p "$LOCAL_APP_DIR"
rsync -a --delete "$BUNDLE/" "$LOCAL_APP_DIR/"

say "Pronto: $TAG_LABEL publicado. Os aparelhos veem o aviso ao abrir o app (ou em Ajustes > Sobre > Procurar atualização)."
