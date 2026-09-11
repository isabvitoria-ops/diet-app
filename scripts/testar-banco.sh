#!/usr/bin/env bash
# Roda as migrações num Postgres limpo e executa a bateria de segurança.
#
# Serve para conferir as políticas de acesso ANTES de subir para o Supabase:
# um erro de RLS descoberto aqui custa um minuto; descoberto em produção,
# custa um vazamento de dado de paciente.
#
# Uso:  PGPORT=5433 PGHOST=/tmp ./scripts/testar-banco.sh
set -euo pipefail

PGHOST="${PGHOST:-/tmp}"
PGPORT="${PGPORT:-5433}"
PGUSER="${PGUSER:-postgres}"
BANCO="${BANCO:-central_teste}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

psql_() { psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -v ON_ERROR_STOP=1 "$@"; }

echo "Recriando o banco $BANCO…"
psql_ -q -d postgres -c "drop database if exists $BANCO;" -c "create database $BANCO;"

echo "Aplicando o ambiente de teste…"
psql_ -q -d "$BANCO" -f "$RAIZ/supabase/testes/00_ambiente.sql" > /dev/null

echo "Aplicando as migrações…"
for arquivo in "$RAIZ"/supabase/migracoes/*.sql; do
  echo "  $(basename "$arquivo")"
  PGOPTIONS="-c client_min_messages=warning" psql_ -q -d "$BANCO" -f "$arquivo" > /dev/null
done

echo "Rodando a bateria de segurança…"
psql_ -d "$BANCO" -f "$RAIZ/supabase/testes/01_acesso.sql" 2>&1 \
  | grep -E "FALHA|passaram|ERROR|falharam" || true
