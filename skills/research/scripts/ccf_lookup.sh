#!/bin/bash
# CCF ranking lookup
# Usage: bash scripts/ccf_lookup.sh "venue_name"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
    echo '{"error": "Usage: bash scripts/ccf_lookup.sh \"venue_name\""}' >&2
    exit 1
fi

DB_FILE="$SKILL_DATA_DIR/ccf_2026.sqlite"
if [[ ! -f "$DB_FILE" ]]; then
    echo "{\"error\": \"CCF database not found at $DB_FILE\"}" >&2
    exit 1
fi

RESULT=$(sqlite3 "$DB_FILE" -json \
    "SELECT acronym, name, rank, field, type, publisher, url
     FROM ccf_2026
     WHERE acronym_alnum LIKE '%${NAME}%'
        OR name LIKE '%${NAME}%'
     LIMIT 5;" 2>/dev/null)

if [[ -z "$RESULT" || "$RESULT" == "[]" ]]; then
    echo "{\"info\": \"No CCF entries matching '$NAME'\"}" >&2
else
    echo "$RESULT" | jq '.[]?'
fi
