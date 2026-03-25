#!/bin/bash
# S2 paper recommendations — given positive/negative example papers
# Usage: bash scripts/s2_recommend.sh "pos_id1,pos_id2" ["neg_id1,neg_id2"] [limit]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

POS_IDS="${1:-}"
NEG_IDS="${2:-}"
LIMIT="${3:-100}"

if [[ -z "$POS_IDS" ]]; then
    echo '{"error": "Usage: bash scripts/s2_recommend.sh \"pos_id1,pos_id2\" [\"neg_id1\"] [limit]"}' >&2
    exit 1
fi

POS_JSON=$(echo "$POS_IDS" | tr ',' '\n' | jq -R . | jq -s .)
NEG_JSON="[]"
if [[ -n "$NEG_IDS" ]]; then
    NEG_JSON=$(echo "$NEG_IDS" | tr ',' '\n' | jq -R . | jq -s .)
fi

JSON_BODY=$(jq -n --argjson pos "$POS_JSON" --argjson neg "$NEG_JSON" \
    '{ positivePaperIds: $pos, negativePaperIds: $neg }')

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract"
API_URL="https://api.semanticscholar.org/recommendations/v1/papers/"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    -X POST "${API_URL}?fields=${FIELDS}&limit=${LIMIT}" \
    -H "Content-Type: application/json" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    -d "$JSON_BODY" \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq '.recommendedPapers[]? | {
            paper_id: .paperId,
            title: .title,
            year: .year,
            venue: ([ .venue, .journal ] | map(select(. != null and . != "")) | map(if type == "object" then .name // "" else . end) | map(select(. != "")) | .[0] // "N/A"),
            citations: .citationCount,
            doi: .externalIds.DOI,
            arxiv_id: .externalIds.ArXiv,
            url: .url,
            authors: [.authors[]? | { name: .name, id: .authorId }][:3],
            source: "s2_recommend"
        }'
        ;;
    429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"S2 recommend HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
