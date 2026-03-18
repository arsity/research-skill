#!/bin/bash
# DOI to BibTeX via content negotiation
# Usage: bash scripts/doi2bibtex.sh "doi"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

DOI="${1:-}"

if [[ -z "$DOI" ]]; then
    echo '{"error": "Usage: bash scripts/doi2bibtex.sh \"doi\""}' >&2
    exit 1
fi

# Clean DOI (strip URL prefix if present)
DOI=$(echo "$DOI" | sed 's|https://doi.org/||g; s|http://doi.org/||g; s|doi.org/||g; s|^ *||; s| *$||')

RESPONSE=$(curl -sL -w "\n%{http_code}" \
    -H "Accept: text/bibliography; style=bibtex" \
    -H "Accept-Language: en" \
    "https://doi.org/${DOI}" \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        if [[ -z "$BODY" ]] || [[ "$BODY" == "<!DOCTYPE"* ]] || [[ "$BODY" == "<html"* ]]; then
            echo "{\"error\": \"Failed to fetch BibTeX for DOI: $DOI (got HTML instead of BibTeX)\"}" >&2
            exit 1
        fi
        echo "$BODY"
        ;;
    404)
        echo "{\"error\": \"DOI not found: $DOI\"}" >&2
        exit 1
        ;;
    406)
        echo "{\"error\": \"BibTeX format not available for DOI: $DOI\"}" >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"DOI HTTP $HTTP_CODE for: $DOI\"}" >&2
        exit 1
        ;;
esac
