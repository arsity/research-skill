#!/bin/bash
# DBLP BibTeX fetch — given a DBLP key, return the .bib entry
# Usage: bash scripts/dblp_bibtex.sh "conf/cvpr/HeZRS16"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

DBLP_KEY="${1:-}"

if [[ -z "$DBLP_KEY" ]]; then
    echo '{"error": "Usage: bash scripts/dblp_bibtex.sh \"dblp_key\""}' >&2
    exit 1
fi

rate_limit "$DBLP_RATE_LIMIT_FILE" "$DBLP_MIN_INTERVAL"

RESPONSE=$(curl -sL \
    "https://dblp.org/rec/${DBLP_KEY}.bib" \
    --max-time 30 2>/dev/null)

if [[ -z "$RESPONSE" ]] || echo "$RESPONSE" | grep -q "404"; then
    echo "{\"error\": \"DBLP BibTeX not found for key: $DBLP_KEY\"}" >&2
    exit 1
fi

echo "$RESPONSE"
