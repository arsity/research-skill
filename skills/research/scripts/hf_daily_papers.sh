#!/bin/bash
# Fetch HF daily (trending) papers
# Usage: bash scripts/hf_daily_papers.sh [limit]

set -e

LIMIT="${1:-20}"

RESPONSE=$(curl -sL \
    "https://huggingface.co/api/daily_papers" \
    --max-time 60 2>/dev/null)

if [[ -z "$RESPONSE" ]]; then
    echo '{"error": "HF daily papers request failed"}' >&2
    exit 1
fi

echo "$RESPONSE" | jq --argjson limit "$LIMIT" '.[:$limit][] | {
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
