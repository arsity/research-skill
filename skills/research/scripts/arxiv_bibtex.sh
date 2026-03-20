#!/bin/bash
# arXiv BibTeX fetch — proper @misc format from arxiv.org
# Usage: bash scripts/arxiv_bibtex.sh "2401.12345"
#
# Returns the official arXiv BibTeX entry with eprint, archivePrefix,
# and primaryClass fields. Use this instead of DBLP's CoRR entries.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

ARXIV_ID="${1:-}"

if [[ -z "$ARXIV_ID" ]]; then
    echo '{"error": "Usage: bash scripts/arxiv_bibtex.sh \"arxiv_id\""}' >&2
    exit 1
fi

# Strip common prefixes
ARXIV_ID="${ARXIV_ID#arXiv:}"
ARXIV_ID="${ARXIV_ID#arxiv:}"

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "https://arxiv.org/bibtex/${ARXIV_ID}" \
    --max-time 30 2>/dev/null) || true

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ -z "$HTTP_CODE" ]] || ! [[ "$HTTP_CODE" =~ ^[0-9]+$ ]]; then
    echo "{\"error\": \"arXiv BibTeX connection failed for ID: $ARXIV_ID\"}" >&2
    exit 1
fi

case "$HTTP_CODE" in
    200)
        if [[ -z "$BODY" ]] || [[ "$BODY" == *"bad_id"* ]]; then
            echo "{\"error\": \"arXiv BibTeX not found for ID: $ARXIV_ID\"}" >&2
            exit 1
        fi
        echo "$BODY"
        ;;
    400)
        echo "{\"error\": \"arXiv invalid ID: $ARXIV_ID\"}" >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"arXiv BibTeX HTTP $HTTP_CODE for ID: $ARXIV_ID\"}" >&2
        exit 1
        ;;
esac
