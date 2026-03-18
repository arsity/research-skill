#!/bin/bash
# Fetch HF daily (trending) papers
# Usage: bash scripts/hf_daily_papers.sh [limit]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

LIMIT="${1:-20}"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "https://huggingface.co/api/daily_papers" \
    --max-time 60 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        if [[ -z "$BODY" ]]; then
            echo '{"error": "HF daily papers returned empty response"}' >&2
            exit 1
        fi
        ;;
    429)
        echo '{"error": "HF rate limit exceeded."}' >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"HF daily papers HTTP $HTTP_CODE\"}" >&2
        exit 1
        ;;
esac

echo "$BODY" | jq --argjson limit "$LIMIT" '.[:$limit][] | {
    title: .paper.title,
    arxiv_id: .paper.id,
    summary: (.paper.summary // "")[:300],
    ai_summary: (.ai_summary // ""),
    ai_keywords: (.ai_keywords // []),
    authors: [.paper.authors[]?.name][:3],
    upvotes: (.paper.upvotes // 0),
    comments: (.numComments // 0),
    published_at: .paper.publishedAt,
    github_repo: (.githubRepo // null),
    github_stars: (.githubStars // null),
    source: "hf_daily"
}'
