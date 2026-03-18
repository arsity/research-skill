#!/bin/bash
# DBLP publication search
# Usage: bash scripts/dblp_search.sh "query" [limit]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
LIMIT="${2:-10}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/dblp_search.sh \"query\" [limit]"}' >&2
    exit 1
fi

rate_limit "$DBLP_RATE_LIMIT_FILE" "$DBLP_MIN_INTERVAL"

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
API_URL="https://dblp.org/search/publ/api"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "${API_URL}?q=${ENCODED_QUERY}&format=json&h=${LIMIT}" \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        TOTAL=$(echo "$BODY" | jq -r '.result.hits["@total"] // "0"')
        if [[ "$TOTAL" == "0" ]]; then
            echo '{"info": "No DBLP results found"}' >&2
        else
            echo "$BODY" | jq '.result.hits.hit[]? | {
        dblp_key: .info.key,
        title: .info.title,
        year: (.info.year | tonumber? // null),
        venue: .info.venue,
        authors: (if .info.authors.author | type == "array" then
            [.info.authors.author[]? | .text][:3]
        else
            [.info.authors.author.text // "N/A"]
        end),
        doi: .info.doi,
        url: .info.url,
        source: "dblp"
    }'
        fi
        ;;
    429)
        echo '{"error": "DBLP rate limit exceeded."}' >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"DBLP HTTP $HTTP_CODE\"}" >&2
        exit 1
        ;;
esac
