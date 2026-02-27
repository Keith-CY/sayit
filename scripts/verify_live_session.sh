#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${1:-$HOME/Library/Application Support/SayIt/history.sqlite}"
SOURCE="${2:-app_live_stream}"

if [[ ! -f "$DB_PATH" ]]; then
  echo "Database not found: $DB_PATH" >&2
  exit 1
fi

LATEST_ID="$(sqlite3 "$DB_PATH" "SELECT id FROM sessions WHERE source='$SOURCE' ORDER BY started_at DESC LIMIT 1;")"
if [[ -z "$LATEST_ID" ]]; then
  echo "No session found for source='$SOURCE'" >&2
  exit 2
fi

echo "DB=$DB_PATH"
echo "SOURCE=$SOURCE"
echo "LATEST_ID=$LATEST_ID"
echo

echo "[session]"
sqlite3 "$DB_PATH" \
  "SELECT id, source, locale, datetime(started_at,'unixepoch','localtime'), CASE WHEN ended_at IS NULL THEN 'open' ELSE 'closed' END FROM sessions WHERE id='$LATEST_ID';"
echo

echo "[counts]"
sqlite3 "$DB_PATH" \
  "SELECT 'segments', COUNT(*) FROM segments WHERE session_id='$LATEST_ID'
   UNION ALL
   SELECT 'audio_assets', COUNT(*) FROM audio_assets WHERE session_id='$LATEST_ID'
   UNION ALL
   SELECT 'pipeline_runs', COUNT(*) FROM pipeline_runs WHERE session_id='$LATEST_ID';"
echo

echo "[latest_text]"
sqlite3 "$DB_PATH" \
  "SELECT sequence, final_text FROM segments WHERE session_id='$LATEST_ID' ORDER BY sequence DESC LIMIT 3;"
