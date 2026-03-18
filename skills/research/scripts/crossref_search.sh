#!/bin/bash
# CrossRef search — fallback for S2
# Usage: bash scripts/crossref_search.sh "query" [limit]

set -e

QUERY="${1:-}"
LIMIT="${2:-20}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/crossref_search.sh \"query\" [limit]"}' >&2
    exit 1
fi

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
API_URL="https://api.crossref.org/works"
FIELDS="DOI,title,author,published-print,published-online,container-title,is-referenced-by-count,URL"

RESPONSE=$(curl -sL \
    "${API_URL}?query=${ENCODED_QUERY}&rows=${LIMIT}&select=${FIELDS}" \
    --max-time 30 2>/dev/null)

if [[ -z "$RESPONSE" ]] || echo "$RESPONSE" | jq -e '.message == null' > /dev/null 2>&1; then
    echo '{"error": "CrossRef API request failed"}' >&2
    exit 1
fi

echo "$RESPONSE" | jq '.message.items[]? | {
    title: (.title[0] // "N/A"),
    year: ((.["published-print"]["date-parts"][0][0] // .["published-online"]["date-parts"][0][0]) // null),
    venue: (.["container-title"][0] // "N/A"),
    citations: (.["is-referenced-by-count"] // 0),
    doi: .DOI,
    url: .URL,
    authors: (([.author[]? | ((.given // "") + " " + (.family // ""))] | if length == 0 then ["N/A"] elif length > 3 then .[:3] + ["et al."] else . end) | join(", ")),
    source: "crossref"
}'
