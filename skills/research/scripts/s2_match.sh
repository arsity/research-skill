#!/bin/bash
# S2 exact title match — returns single closest match
# Usage: bash scripts/s2_match.sh "paper title"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/s2_match.sh \"paper title\""}' >&2
    exit 1
fi

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"
API_URL="https://api.semanticscholar.org/graph/v1/paper/search/match"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "${API_URL}?query=${ENCODED_QUERY}&fields=${FIELDS}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" '.data[0]? |
            select(. != null) |
            ([ .venue, .journal ] | map(select(. != null and . != "")) | .[0] // "N/A") as $venue |
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
                open_access_pdf: (.openAccessPdf.url // null),
                is_arxiv: $is_arxiv,
                arxiv_status: $arxiv_status,
                authors: [.authors[]? | { name: .name, id: .authorId }][:3],
                source: "s2"
            }'
        ;;
    404) echo '{"error": "No matching paper found"}' >&2; exit 1 ;;
    429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"S2 match HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
