#!/bin/bash
# Impact factor lookup
# Usage: bash scripts/if_lookup.sh "journal_name"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
    echo '{"error": "Usage: bash scripts/if_lookup.sh \"journal_name\""}' >&2
    exit 1
fi

DB_FILE="$SKILL_DATA_DIR/impact_factor.sqlite3"
if [[ ! -f "$DB_FILE" ]]; then
    echo "{\"error\": \"Impact factor database not found at $DB_FILE\"}" >&2
    exit 1
fi

RESULT=$(sqlite3 "$DB_FILE" -json \
    "SELECT journal, factor, jcr, zky
     FROM factor
     WHERE journal LIKE '%${NAME}%'
     ORDER BY factor DESC
     LIMIT 5;" 2>/dev/null)

if [[ -z "$RESULT" || "$RESULT" == "[]" ]]; then
    echo "{\"info\": \"No impact factor entries matching '$NAME'\"}" >&2
else
    echo "$RESULT" | jq '.[]?'
fi
