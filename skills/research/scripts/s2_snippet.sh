#!/bin/bash
# S2 snippet search — find ~500-word passages matching a query in paper bodies
# Usage: bash scripts/s2_snippet.sh "query" [limit]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
LIMIT="${2:-10}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/s2_snippet.sh \"query\" [limit]"}' >&2
    exit 1
fi

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
API_URL="https://api.semanticscholar.org/graph/v1/snippet/search"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "${API_URL}?query=${ENCODED_QUERY}&limit=${LIMIT}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq '.data[]? | {
            paper_id: .paper.corpusId,
            title: .paper.title,
            authors: [.paper.authors[]?][:3],
            snippet: .snippet.text,
            snippet_section: .snippet.section,
            source: "s2_snippet"
        }'
        ;;
    429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"S2 snippet HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
