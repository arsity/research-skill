#!/bin/bash
# S2 author info — h-index, citation count, paper count
# Usage: bash scripts/author_info.sh "author_id"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

AUTHOR_ID="${1:-}"

if [[ -z "$AUTHOR_ID" ]]; then
    echo '{"error": "Usage: bash scripts/author_info.sh \"author_id\""}' >&2
    exit 1
fi

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

API_URL="https://api.semanticscholar.org/graph/v1/author/${AUTHOR_ID}"
FIELDS="name,hIndex,citationCount,paperCount,affiliations,homepage,url"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "${API_URL}?fields=${FIELDS}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq '{
            name: .name,
            hIndex: .hIndex,
            citations: .citationCount,
            papers: .paperCount,
            affiliations: (.affiliations // []),
            homepage: .homepage,
            url: .url
        }'
        ;;
    404) echo '{"error": "Author not found"}' >&2; exit 1 ;;
    429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"S2 HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
