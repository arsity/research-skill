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

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "https://dblp.org/rec/${DBLP_KEY}.bib" \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        if [[ -z "$BODY" ]]; then
            echo "{\"error\": \"DBLP BibTeX empty for key: $DBLP_KEY\"}" >&2
            exit 1
        fi
        echo "$BODY"
        ;;
    404)
        echo "{\"error\": \"DBLP BibTeX not found for key: $DBLP_KEY\"}" >&2
        exit 1
        ;;
    429)
        echo '{"error": "DBLP rate limit exceeded."}' >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"DBLP BibTeX HTTP $HTTP_CODE\"}" >&2
        exit 1
        ;;
esac
