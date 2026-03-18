#!/bin/bash
# CrossRef search — fallback for S2
# Usage: bash scripts/crossref_search.sh "query" [limit]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
LIMIT="${2:-20}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/crossref_search.sh \"query\" [limit]"}' >&2
    exit 1
fi

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
API_URL="https://api.crossref.org/works"
FIELDS="DOI,title,author,published-print,published-online,container-title,is-referenced-by-count,URL"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "${API_URL}?query=${ENCODED_QUERY}&rows=${LIMIT}&select=${FIELDS}" \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        if [[ -z "$BODY" ]] || ! echo "$BODY" | jq -e '.message' > /dev/null 2>&1; then
            echo '{"error": "CrossRef API returned invalid response"}' >&2
            exit 1
        fi
        TOTAL=$(echo "$BODY" | jq -r '.message["total-results"] // 0')
        if [[ "$TOTAL" == "0" ]]; then
            echo '{"info": "No CrossRef results found"}' >&2
            exit 0
        fi
        ;;
    429)
        echo '{"error": "CrossRef rate limit exceeded."}' >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"CrossRef HTTP $HTTP_CODE\"}" >&2
        exit 1
        ;;
esac

echo "$BODY" | jq '.message.items[]? | {
    title: (.title[0] // "N/A"),
    year: ((.["published-print"]["date-parts"][0][0] // .["published-online"]["date-parts"][0][0]) // null),
    venue: (.["container-title"][0] // "N/A"),
    citations: (.["is-referenced-by-count"] // 0),
    doi: .DOI,
    url: .URL,
    authors: (([.author[]? | ((.given // "") + " " + (.family // ""))] | if length == 0 then ["N/A"] elif length > 3 then .[:3] + ["et al."] else . end) | join(", ")),
    source: "crossref"
}'
