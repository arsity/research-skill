#!/bin/bash
# S2 boolean bulk search — broader queries, sortable, up to 1000/call
# Usage: bash scripts/s2_bulk_search.sh "query" [year_range] [limit]
# Example: bash scripts/s2_bulk_search.sh "deep learning" "2020-" 50

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
YEAR_RANGE="${2:-}"
LIMIT="${3:-50}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/s2_bulk_search.sh \"query\" [year_range] [limit]"}' >&2
    exit 1
fi

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
API_URL="https://api.semanticscholar.org/graph/v1/paper/search/bulk"
FIELDS="title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"

PARAMS="query=${ENCODED_QUERY}&limit=${LIMIT}&fields=${FIELDS}"
if [[ -n "$YEAR_RANGE" ]]; then
    PARAMS="${PARAMS}&year=${YEAR_RANGE}"
fi

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "${API_URL}?${PARAMS}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 60 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        TOTAL=$(echo "$BODY" | jq -r '.total // 0')
        if [[ "$TOTAL" == "0" ]]; then
            echo '{"info": "No S2 bulk results found"}' >&2
            exit 0
        fi
        RETURNED=$(echo "$BODY" | jq -r '.data | length')
        echo "{\"total\": $TOTAL, \"returned\": $RETURNED}" >&2

        echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" --argjson req_limit "$LIMIT" '.data[:$req_limit][]? |
            ([ .venue, .journal ] | map(select(. != null and . != "")) | map(if type == "object" then .name // "" else . end) | map(select(. != "")) | .[0] // "N/A") as $venue |
            ($venue | test("(?i)arxiv")) as $is_arxiv |
            (if $is_arxiv and .citationCount < ($threshold | tonumber) then "caution"
             elif $is_arxiv and .citationCount >= ($threshold | tonumber) then "recommended"
             else "normal" end) as $arxiv_status |
            {
                paper_id: .paperId,
                title: .title,
                year: .year,
                venue: $venue,
                citations: .citationCount,
                doi: .externalIds.DOI,
                arxiv_id: .externalIds.ArXiv,
                url: .url,
                abstract: (.abstract // ""),
                open_access_pdf: (.openAccessPdf.url // null),
                is_arxiv: $is_arxiv,
                arxiv_status: $arxiv_status,
                authors: [.authors[]? | { name: .name, id: .authorId }][:3],
                source: "s2"
            }'
        ;;
    429)
        echo '{"error": "S2 rate limit exceeded. Wait 60 seconds."}' >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"S2 HTTP $HTTP_CODE\"}" >&2
        exit 1
        ;;
esac
