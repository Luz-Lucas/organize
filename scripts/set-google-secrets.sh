#!/usr/bin/env bash
# Grava o ID e a chave secreta do cliente OAuth do Google nos segredos do Supabase.
# Os valores são digitados aqui (a chave fica oculta) e não aparecem no histórico.
set -euo pipefail
cd "$(dirname "$0")/.."
read -rp "ID do cliente (termina em .apps.googleusercontent.com): " CID
read -rsp "Chave secreta do cliente (não aparece ao digitar): " CSECRET; echo
[[ "$CID" == *.apps.googleusercontent.com ]] || { echo "ID inválido"; exit 1; }
[[ -n "$CSECRET" ]] || { echo "Chave vazia"; exit 1; }
npx supabase secrets set GOOGLE_CLIENT_ID="$CID" GOOGLE_CLIENT_SECRET="$CSECRET" --project-ref dgarojxettnppcahedvk >/dev/null
unset CSECRET
echo "Pronto: GOOGLE_CLIENT_ID e GOOGLE_CLIENT_SECRET gravados no Supabase."
