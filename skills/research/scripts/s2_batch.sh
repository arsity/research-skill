#!/bin/bash
# S2 batch paper metadata — NOT a search. Takes known paper IDs, returns details.
# Usage: bash scripts/s2_batch.sh "id1" "id2" ... (up to 500)
# Also accepts IDs via stdin (one per line)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

# Collect IDs from arguments or stdin
IDS=()
if [[ $# -gt 0 ]]; then
    IDS=("$@")
elif [[ ! -t 0 ]]; then
    while IFS= read -r line; do
        [[ -n "$line" ]] && IDS+=("$line")
    done
fi

if [[ ${#IDS[@]} -eq 0 ]]; then
    echo '{"error": "Usage: bash scripts/s2_batch.sh id1 id2 ... (or pipe IDs via stdin)"}' >&2
    exit 1
fi

FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"
API_URL="https://api.semanticscholar.org/graph/v1/paper/batch"

# Chunk into groups of 500
CHUNK_SIZE=500
for ((i=0; i<${#IDS[@]}; i+=CHUNK_SIZE)); do
    CHUNK=("${IDS[@]:i:CHUNK_SIZE}")

    # Build JSON body
    JSON_BODY=$(printf '%s\n' "${CHUNK[@]}" | jq -R . | jq -s '{ ids: . }')

    rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

    RESPONSE=$(curl -sL -w "\n%{http_code}" \
        -X POST "$API_URL?fields=$FIELDS" \
        -H "Content-Type: application/json" \
        ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
        -d "$JSON_BODY" \
        --max-time 60 2>/dev/null)

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    case "$HTTP_CODE" in
        200)
            echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" '.[]? | select(. != null) |
                (.venue // .journal // "") as $venue |
                ($venue | test("(?i)arxiv")) as $is_arxiv |
                (if $is_arxiv and .citationCount < ($threshold | tonumber) then "caution"
                 elif $is_arxiv and .citationCount >= ($threshold | tonumber) then "recommended"
                 else "normal" end) as $arxiv_status |
                {
                    paper_id: .paperId,
                    title: .title,
                    year: .year,
                    venue: ($venue // "N/A"),
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
        429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
        *)   echo "{\"error\": \"S2 batch HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
    esac
done
