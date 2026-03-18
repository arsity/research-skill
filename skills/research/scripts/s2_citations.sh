#!/bin/bash
# S2 citation traversal — find papers that cited a given paper
# Usage: bash scripts/s2_citations.sh "paper_id" [limit]
# Returns: JSON objects (one per line), each with paper_id, title, year, venue, citations, etc.

set -e

# Init
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

PAPER_ID="${1:-}"
LIMIT="${2:-100}"

if [[ -z "$PAPER_ID" ]]; then
    echo '{"error": "Usage: bash scripts/s2_citations.sh \"paper_id\" [limit]"}' >&2
    exit 1
fi

# Rate limit
rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

# Request
FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"
API_URL="https://api.semanticscholar.org/graph/v1/paper/${PAPER_ID}/citations"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "${API_URL}?fields=${FIELDS}&limit=${LIMIT}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" '.data[]?.citingPaper |
            select(.paperId != null) |
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
    429)
        echo '{"error": "S2 rate limit exceeded."}' >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"S2 HTTP $HTTP_CODE\"}" >&2
        exit 1
        ;;
esac
