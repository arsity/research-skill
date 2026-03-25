#!/bin/bash
# S2 relevance-ranked semantic search
# Usage: bash scripts/s2_search.sh "query" [limit]
# Returns: JSON objects (one per line), each with title, year, venue, citations, etc.

set -e

# Init
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
LIMIT="${2:-20}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/s2_search.sh \"query\" [limit]"}' >&2
    exit 1
fi

# Rate limit
rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

# URL encode
ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)

# Request
API_URL="https://api.semanticscholar.org/graph/v1/paper/search"
FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "${API_URL}?query=${ENCODED_QUERY}&limit=${LIMIT}&fields=${FIELDS}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        TOTAL=$(echo "$BODY" | jq -r '.total // 0')
        if [[ "$TOTAL" == "0" ]]; then
            echo '{"info": "No S2 results found"}' >&2
            exit 0
        fi
        echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" '.data[]? |
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
        echo '{"error": "S2 rate limit exceeded. Wait and retry, or use s2_bulk_search.sh"}' >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"S2 HTTP $HTTP_CODE\"}" >&2
        exit 1
        ;;
esac
