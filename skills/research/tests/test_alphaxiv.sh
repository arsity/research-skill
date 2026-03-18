#!/bin/bash
# Tests for AlphaXiv curl access
# Verifies redirect handling (-L) and content integrity

set -e
PASS=0; FAIL=0
PAPER_ID="2401.10891"  # Depth Anything paper, stable on alphaxiv

check() {
    local desc="$1" result="$2" expected="$3"
    if [[ "$result" == "$expected" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (got: $result)"
        FAIL=$((FAIL + 1))
    fi
}

echo "Test 1: alphaxiv.org redirects to www.alphaxiv.org..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://alphaxiv.org/overview/${PAPER_ID}.md")
check "non-L curl gets 301" "$HTTP_CODE" "301"

echo "Test 2: curl -sL follows redirect and gets 200..."
HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "https://alphaxiv.org/overview/${PAPER_ID}.md")
check "curl -sL gets 200" "$HTTP_CODE" "200"

echo "Test 3: overview content is non-empty..."
CONTENT=$(curl -sL "https://alphaxiv.org/overview/${PAPER_ID}.md")
if [[ -n "$CONTENT" && ${#CONTENT} -gt 100 ]]; then
    echo "  PASS: Got ${#CONTENT} chars"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Empty or too short (${#CONTENT} chars)"
    FAIL=$((FAIL + 1))
fi

echo "Test 4: overview content contains paper title keywords..."
if echo "$CONTENT" | grep -qi "depth\|anything\|unlabeled\|monocular"; then
    echo "  PASS: Content matches expected paper"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Content does not mention expected keywords"
    FAIL=$((FAIL + 1))
fi

echo "Test 5: abs endpoint also follows redirect and gets 200..."
HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "https://alphaxiv.org/abs/${PAPER_ID}.md")
check "abs endpoint curl -sL gets 200" "$HTTP_CODE" "200"

echo "Test 6: 404 on non-existent paper returns 404..."
HTTP_CODE=$(curl -sL -o /dev/null -w "%{http_code}" "https://alphaxiv.org/overview/0000.00000.md")
check "non-existent paper returns 404" "$HTTP_CODE" "404"

echo "---"
echo "alphaxiv: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
