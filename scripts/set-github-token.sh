#!/usr/bin/env bash
# Grava o token do GitHub (fine-grained) nos segredos do Supabase. O token não aparece ao digitar.
set -euo pipefail
cd "$(dirname "$0")/.."
read -rsp "Token do GitHub (começa com github_pat_; não aparece ao digitar): " TOKEN; echo
[[ "$TOKEN" == github_pat_* ]] || { echo "Token inválido (esperado github_pat_...)"; exit 1; }
npx supabase secrets set GITHUB_TOKEN="$TOKEN" --project-ref dgarojxettnppcahedvk >/dev/null
unset TOKEN
echo "Pronto: GITHUB_TOKEN gravado no Supabase."
