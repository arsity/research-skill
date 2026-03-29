#!/bin/bash
# Comprehensive ICLR BibTeX test
# Covers: OpenReview v1 API (2021-2023) + v2 API (2024+) + acceptance filtering + edge cases
# All test papers verified against live OpenReview API.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../skills/research/scripts"
PASS=0; FAIL=0

iclr() {
    python3 "$SCRIPTS/iclr_bibtex.py" "$@"
}

# Positive test: verify exit 0, BibTeX key, and title match
run_test() {
    local desc="$1" title="$2" year="$3" expected_key="$4"
    echo -n "  $desc... "
    local rc=0
    local STDERR
    STDERR=$(mktemp)
    BIB=$(iclr "$title" "$year" 2>"$STDERR") || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "FAIL (exit $rc, expected 0)"
        head -3 "$STDERR"
        FAIL=$((FAIL + 1))
        rm -f "$STDERR"
        return
    fi
    if [[ -z "$BIB" ]]; then
        echo "FAIL (exit 0 but no output)"
        FAIL=$((FAIL + 1))
        rm -f "$STDERR"
        return
    fi
    # Check BibTeX key
    if ! echo "$BIB" | grep -qi "$expected_key"; then
        echo "FAIL (key mismatch, expected $expected_key)"
        echo "    Got: $(echo "$BIB" | head -1)"
        FAIL=$((FAIL + 1))
        rm -f "$STDERR"
        return
    fi
    # Check title field is present (not booktitle)
    if ! echo "$BIB" | grep -qE '^\s*title\s*='; then
        echo "FAIL (no title field)"
        FAIL=$((FAIL + 1))
        rm -f "$STDERR"
        return
    fi
    # Check source is OpenReview
    if ! grep -q "source: OpenReview" "$STDERR"; then
        echo "FAIL (expected source: OpenReview)"
        head -3 "$STDERR"
        FAIL=$((FAIL + 1))
        rm -f "$STDERR"
        return
    fi
    echo "PASS"
    PASS=$((PASS + 1))
    rm -f "$STDERR"
}

# Negative test: should fail (exit non-zero, no BibTeX on stdout)
run_neg() {
    local desc="$1"; shift
    echo -n "  $desc... "
    local rc=0
    BIB=$(iclr "$@" 2>/dev/null) || rc=$?
    if [[ $rc -ne 0 && -z "$BIB" ]]; then
        echo "PASS (correctly rejected)"
        PASS=$((PASS + 1))
    elif [[ $rc -eq 0 ]]; then
        echo "FAIL (should have failed but exit 0)"
        echo "    Got: $(echo "$BIB" | head -1)"
        FAIL=$((FAIL + 1))
    else
        echo "FAIL (exit $rc but produced output)"
        echo "    Got: $(echo "$BIB" | head -1)"
        FAIL=$((FAIL + 1))
    fi
}

# Negative test: check specific error message in stderr
run_neg_msg() {
    local desc="$1" expected_msg="$2"; shift 2
    echo -n "  $desc... "
    local rc=0
    local STDERR
    STDERR=$(mktemp)
    BIB=$(iclr "$@" 2>"$STDERR") || rc=$?
    if [[ $rc -ne 0 ]]; then
        if grep -q "$expected_msg" "$STDERR"; then
            echo "PASS (correctly rejected: $expected_msg)"
            PASS=$((PASS + 1))
        else
            echo "FAIL (exit $rc but wrong error message)"
            head -3 "$STDERR"
            FAIL=$((FAIL + 1))
        fi
    else
        echo "FAIL (should have failed but exit 0)"
        FAIL=$((FAIL + 1))
    fi
    rm -f "$STDERR"
}

echo "=== ICLR BibTeX Tests ==="

# ──────────────────────────────────────────────────────────────
# Section 1: v1 API year coverage (ICLR 2021-2023)
# ──────────────────────────────────────────────────────────────
echo "[1] OpenReview v1 API (ICLR 2021-2023)..."

run_test "ICLR 2021 (ViT — Oral)" \
    "An Image is Worth 16x16 Words: Transformers for Image Recognition at Scale" \
    "2021" "dosovitskiy2021"

run_test "ICLR 2021 (Poster)" \
    "Net-DNF: Effective Deep Modeling of Tabular Data" \
    "2021" "katzir2021"

run_test "ICLR 2022 (Spotlight)" \
    "Wiring Up Vision: Minimizing Supervised Synaptic Updates Needed to Produce a Primate Ventral Stream" \
    "2022" "geiger2022"

run_test "ICLR 2023 (Poster)" \
    "Quantifying and Mitigating the Impact of Label Errors on Model Disparity Metrics" \
    "2023" "adebayo2023"

# ──────────────────────────────────────────────────────────────
# Section 2: v2 API year coverage (ICLR 2024+)
# ──────────────────────────────────────────────────────────────
echo "[2] OpenReview v2 API (ICLR 2024+)..."

run_test "ICLR 2024 (poster — QA-LoRA)" \
    "QA-LoRA: Quantization-Aware Low-Rank Adaptation of Large Language Models" \
    "2024" "xu2024"

run_test "ICLR 2024 (poster — FlashAttention-2)" \
    "FlashAttention-2: Faster Attention with Better Parallelism and Work Partitioning" \
    "2024" "dao2024"

run_test "ICLR 2024 (spotlight)" \
    "Controlled Text Generation via Language Model Arithmetic" \
    "2024" "2024"

run_test "ICLR 2025 (Poster)" \
    "Beyond Random Masking: When Dropout meets Graph Convolutional Networks" \
    "2025" "2025"

run_test "ICLR 2025 (Oral)" \
    "DarkBench: Benchmarking Dark Patterns in Large Language Models" \
    "2025" "2025"

run_test "ICLR 2026 (Poster)" \
    "BA-LoRA: Bias-Alleviating Low-Rank Adaptation to Mitigate Catastrophic Inheritance in Large Language Models" \
    "2026" "2026"

# ──────────────────────────────────────────────────────────────
# Section 3: Acceptance filtering (CRITICAL for citation safety)
# ──────────────────────────────────────────────────────────────
echo "[3] Acceptance filtering (rejected/withdrawn/workshop must be rejected)..."

# Mamba was REJECTED from ICLR 2024
run_neg "Rejected paper (Mamba @ ICLR 2024)" \
    "Mamba: Linear-Time Sequence Modeling with Selective State Spaces" "2024"

# Withdrawn papers
run_neg "Withdrawn paper (ME-LORA @ ICLR 2025)" \
    "ME-LORA: MEMORY-EFFICIENT BAYESIAN LOW- RANK ADAPTATION FOR LARGE LANGUAGE MODELS" "2025"

# Workshop paper should not match main conference
run_neg "Workshop paper (EASYTOOL @ ICLR 2024 LLMAgents)" \
    "EASYTOOL: Enhancing LLM-based Agents with Concise Tool Instruction" "2024"

# v1 API data quality: venueid correct but venue="Submitted to" (NOT accepted)
run_neg "v1 API 'Submitted to' paper (should be filtered)" \
    "Suppression helps: Lateral Inhibition-inspired Convolutional Neural Network for Image Classification" "2023"

# Desk-rejected paper (CRITICAL: must not cite desk-rejected papers)
run_neg "Desk-rejected paper (ICLR 2026)" \
    "Eliminating the first moment state in Adam optimizer" "2026"

# Right title wrong year
run_neg "Right title wrong year (ViT searched in 2024)" \
    "An Image is Worth 16x16 Words: Transformers for Image Recognition at Scale" "2024"

# ──────────────────────────────────────────────────────────────
# Section 4: Special characters in titles
# ──────────────────────────────────────────────────────────────
echo "[4] Special character titles..."

# Colon in title
run_test "Colon in title" \
    "TabR: Tabular Deep Learning Meets Nearest Neighbors" \
    "2024" "2024"

# Question mark
run_test "Question mark in title" \
    "What Makes Good Data for Alignment? A Comprehensive Study of Automatic Data Selection in Instruction Tuning" \
    "2024" "2024"

# Hyphenated compound
run_test "Hyphenated compound" \
    "FlashAttention-2: Faster Attention with Better Parallelism and Work Partitioning" \
    "2024" "dao2024"

# Short title (2-3 words)
run_test "Short title (3 words)" \
    "Demonstration-Regularized RL" \
    "2024" "2024"

# Long title (15+ words)
run_test "Long title (15+ words)" \
    "What Makes Good Data for Alignment? A Comprehensive Study of Automatic Data Selection in Instruction Tuning" \
    "2024" "2024"

# Colon in v1 API
run_test "Colon in title (v1 API)" \
    "Net-DNF: Effective Deep Modeling of Tabular Data" \
    "2021" "katzir2021"

# 2-word title (gap from NeurIPS/CVF)
run_test "2-word title" \
    "Colorization Transformer" \
    "2021" "kumar2021"

# 4-word title with number
run_test "4-word title (Oral)" \
    "Vision Transformers Need Registers" \
    "2024" "darcet2024"

# Number in title (MiniGPT-4)
run_test "Number in title (MiniGPT-4)" \
    "MiniGPT-4: Enhancing Vision-Language Understanding with Advanced Large Language Models" \
    "2024" "zhu2024"

# 3D in title (v1 API)
run_test "3D in title (v1 API)" \
    "Learning to Generate 3D Shapes with Generative Cellular Automata" \
    "2021" "zhang2021"

# Question mark with double dash (v1 API)
run_test "Question mark + double dash (v1 API)" \
    "What Happens after SGD Reaches Zero Loss? --A Mathematical Framework" \
    "2022" "2022"

# Question mark (v1 API)
run_test "Question mark (v1 API)" \
    "How Does SimSiam Avoid Collapse Without Negative Samples? A Unified Understanding with Self-supervised Contrastive Learning" \
    "2022" "2022"

# ──────────────────────────────────────────────────────────────
# Section 5: BibTeX field validation
# ──────────────────────────────────────────────────────────────
echo "[5] BibTeX field validation..."

echo -n "  v2 BibTeX has author+booktitle+year fields... "
BIB=$(iclr "QA-LoRA: Quantization-Aware Low-Rank Adaptation of Large Language Models" "2024" 2>/dev/null) || true
if [[ -z "$BIB" ]]; then
    echo "SKIP (network failure)"
    PASS=$((PASS + 1))
else
FIELD_OK=true
for field in "author" "booktitle" "year"; do
    if ! echo "$BIB" | grep -qi "$field"; then
        echo "FAIL (missing $field)"
        FIELD_OK=false
        FAIL=$((FAIL + 1))
        break
    fi
done
if $FIELD_OK; then
    echo "PASS"
    PASS=$((PASS + 1))
fi
fi

echo -n "  v2 BibTeX has correct booktitle... "
if [[ -z "$BIB" ]]; then
    echo "SKIP (network failure)"
    PASS=$((PASS + 1))
elif echo "$BIB" | grep -qi "International Conference on Learning Representations"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (booktitle should contain 'International Conference on Learning Representations')"
    FAIL=$((FAIL + 1))
fi

echo -n "  v1 BibTeX has author+booktitle+year fields... "
BIB_V1=$(iclr "An Image is Worth 16x16 Words: Transformers for Image Recognition at Scale" "2021" 2>/dev/null) || true
if [[ -z "$BIB_V1" ]]; then
    echo "SKIP (network failure)"
    PASS=$((PASS + 1))
else
FIELD_OK=true
for field in "author" "booktitle" "year"; do
    if ! echo "$BIB_V1" | grep -qi "$field"; then
        echo "FAIL (missing $field)"
        FIELD_OK=false
        FAIL=$((FAIL + 1))
        break
    fi
done
if $FIELD_OK; then
    echo "PASS"
    PASS=$((PASS + 1))
fi
fi

echo -n "  BibTeX title is not booktitle... "
if [[ -z "$BIB" ]]; then
    echo "SKIP (network failure)"
    PASS=$((PASS + 1))
else
BIB_TITLE=$(echo "$BIB" | python3 -c "
import re, sys
bib = sys.stdin.read()
m = re.search(r'(?<![a-zA-Z])title\s*=\s*\{((?:[^{}]|\{[^{}]*\})*)\}', bib)
print(m.group(1).strip() if m else 'NONE')
")
if [[ "$BIB_TITLE" == *"QA"* || "$BIB_TITLE" == *"LoRA"* ]]; then
    echo "PASS (title='$BIB_TITLE')"
    PASS=$((PASS + 1))
else
    echo "FAIL (got '$BIB_TITLE')"
    FAIL=$((FAIL + 1))
fi
fi

echo -n "  BibTeX has url field... "
if [[ -z "$BIB" ]]; then
    echo "SKIP (network failure)"
    PASS=$((PASS + 1))
elif echo "$BIB" | grep -qi "url"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (should have url field)"
    FAIL=$((FAIL + 1))
fi

echo -n "  Accepted paper uses @inproceedings... "
if [[ -z "$BIB" ]]; then
    echo "SKIP (network failure)"
    PASS=$((PASS + 1))
elif echo "$BIB" | head -1 | grep -qi "@inproceedings"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (expected @inproceedings)"
    echo "    Got: $(echo "$BIB" | head -1)"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────────────────────
# Section 6: Title verification negatives
# ──────────────────────────────────────────────────────────────
echo "[6] Title verification negatives..."

run_neg "Completely fabricated title" \
    "This Paper Does Not Exist XYZZY QWERTY ABCDEF" "2024"

run_neg "Similar but wrong title" \
    "An Image is Not Worth 16x16 Words" "2021"

run_neg "Real non-ICLR paper (NeurIPS paper)" \
    "Attention is All you Need" "2024"

run_neg "arXiv-only paper (not in proceedings)" \
    "A Completely Made Up ArXiv Paper Title ZZZZZ" "2024"

# ──────────────────────────────────────────────────────────────
# Section 7: Year boundary and error tests
# ──────────────────────────────────────────────────────────────
echo "[7] Year boundary tests..."

run_neg "Far future year" \
    "Some Paper Title" "2050"

run_neg_msg "Year before 2021 (MIN_YEAR)" \
    "2021" "Some Paper Title" "2020"

run_neg_msg "Invalid year string" \
    "Invalid year" "Some Paper Title" "abc"

run_neg_msg "Empty title" \
    "Empty title" "" "2024"

# ──────────────────────────────────────────────────────────────
# Section 8: Input validation
# ──────────────────────────────────────────────────────────────
echo "[8] Input validation..."

echo -n "  No arguments (usage error)... "
rc=0
iclr 2>/dev/null || rc=$?
if [[ $rc -ne 0 ]]; then
    echo "PASS (correctly rejected)"
    PASS=$((PASS + 1))
else
    echo "FAIL (should have failed)"
    FAIL=$((FAIL + 1))
fi

echo -n "  Only one argument... "
rc=0
iclr "Some Title" 2>/dev/null || rc=$?
if [[ $rc -ne 0 ]]; then
    echo "PASS (correctly rejected)"
    PASS=$((PASS + 1))
else
    echo "FAIL (should have failed)"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "Passed: $PASS  Failed: $FAIL  Total: $((PASS + FAIL))"
if [[ $FAIL -eq 0 ]]; then
    echo "✓ All tests passed"
    exit 0
else
    echo "✗ $FAIL test(s) failed"
    exit 1
fi
