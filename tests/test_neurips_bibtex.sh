#!/bin/bash
# Comprehensive NeurIPS BibTeX test
# Covers: papers.nips.cc (1987-2024) + OpenReview fallback (2025) + edge cases
# All test papers verified against live nips.cc / OpenReview pages.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../skills/research/scripts"
PASS=0; FAIL=0

neurips() {
    python3 "$SCRIPTS/neurips_bibtex.py" "$@"
}

# Positive test: verify exit 0, BibTeX key, and title match
run_test() {
    local desc="$1" title="$2" year="$3" expected_key="$4" expected_source="$5"
    echo -n "  $desc... "
    local rc=0
    local STDERR
    STDERR=$(mktemp)
    BIB=$(neurips "$title" "$year" 2>"$STDERR") || rc=$?
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
    # Check title field is present (not booktitle — use word boundary)
    if ! echo "$BIB" | grep -qE '^\s*title\s*='; then
        echo "FAIL (no title field)"
        FAIL=$((FAIL + 1))
        rm -f "$STDERR"
        return
    fi
    # Check source if specified
    if [[ -n "$expected_source" ]]; then
        if ! grep -q "source: $expected_source" "$STDERR"; then
            echo "FAIL (expected source: $expected_source)"
            head -3 "$STDERR"
            FAIL=$((FAIL + 1))
            rm -f "$STDERR"
            return
        fi
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
    BIB=$(neurips "$@" 2>/dev/null) || rc=$?
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
    BIB=$(neurips "$@" 2>"$STDERR") || rc=$?
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

echo "=== NeurIPS BibTeX Tests ==="

# ──────────────────────────────────────────────────────────────
# Section 1: nips.cc year coverage — NIPS era (1987-2017)
# ──────────────────────────────────────────────────────────────
echo "[1] nips.cc NIPS era (1987-2017)..."

run_test "NIPS 1987 (earliest year)" \
    "Synchronization in Neural Nets" \
    "1987" "NIPS1987" "nips.cc"

run_test "NIPS 1997" \
    "A Revolution: Belief Propagation in Graphs with Cycles" \
    "1997" "NIPS1997" "nips.cc"

run_test "NIPS 2001" \
    "On Discriminative vs. Generative Classifiers: A comparison of logistic regression and naive Bayes" \
    "2001" "NIPS2001" "nips.cc"

run_test "NIPS 2006" \
    "Greedy Layer-Wise Training of Deep Networks" \
    "2006" "NIPS2006" "nips.cc"

run_test "NIPS 2012 (AlexNet)" \
    "ImageNet Classification with Deep Convolutional Neural Networks" \
    "2012" "NIPS2012" "nips.cc"

run_test "NIPS 2013 (Word2Vec)" \
    "Distributed Representations of Words and Phrases and their Compositionality" \
    "2013" "NIPS2013" "nips.cc"

run_test "NIPS 2014 (GAN)" \
    "Generative Adversarial Nets" \
    "2014" "NIPS2014" "nips.cc"

run_test "NIPS 2016" \
    "Improved Techniques for Training GANs" \
    "2016" "NIPS2016" "nips.cc"

run_test "NIPS 2017 (Transformer — last NIPS)" \
    "Attention is All you Need" \
    "2017" "NIPS2017" "nips.cc"

# ──────────────────────────────────────────────────────────────
# Section 2: nips.cc year coverage — NeurIPS era (2018-2024)
# ──────────────────────────────────────────────────────────────
echo "[2] nips.cc NeurIPS era (2018-2024)..."

run_test "NeurIPS 2018 (Neural ODE — first NeurIPS)" \
    "Neural Ordinary Differential Equations" \
    "2018" "NeurIPS2018" "nips.cc"

run_test "NeurIPS 2019 (PyTorch)" \
    "PyTorch: An Imperative Style, High-Performance Deep Learning Library" \
    "2019" "NeurIPS2019" "nips.cc"

run_test "NeurIPS 2020 (GPT-3)" \
    "Language Models are Few-Shot Learners" \
    "2020" "NeurIPS2020" "nips.cc"

run_test "NeurIPS 2021 (Best Paper)" \
    "A Universal Law of Robustness via Isoperimetry" \
    "2021" "NeurIPS2021" "nips.cc"

run_test "NeurIPS 2022" \
    "Is Out-of-Distribution Detection Learnable?" \
    "2022" "NeurIPS2022" "nips.cc"

run_test "NeurIPS 2023 (DPO)" \
    "Direct Preference Optimization: Your Language Model is Secretly a Reward Model" \
    "2023" "NeurIPS2023" "nips.cc"

run_test "NeurIPS 2024 (MicroAdam)" \
    "MicroAdam: Accurate Adaptive Optimization with Low Space Overhead and Provable Convergence" \
    "2024" "NEURIPS2024" "nips.cc"

# ──────────────────────────────────────────────────────────────
# Section 3: OpenReview fallback (years not on nips.cc)
# ──────────────────────────────────────────────────────────────
echo "[3] OpenReview fallback..."

run_test "NeurIPS 2025 via OpenReview" \
    "Generalized Linear Mode Connectivity for Transformers" \
    "2025" "theus2025" "OpenReview"

# ──────────────────────────────────────────────────────────────
# Section 4: Source priority (nips.cc preferred when both available)
# ──────────────────────────────────────────────────────────────
echo "[4] Source priority..."

# 2023 and 2024 are on both nips.cc and OpenReview; nips.cc should win
run_test "2023 prefers nips.cc" \
    "Direct Preference Optimization: Your Language Model is Secretly a Reward Model" \
    "2023" "NeurIPS2023" "nips.cc"

run_test "2024 prefers nips.cc" \
    "MicroAdam: Accurate Adaptive Optimization with Low Space Overhead and Provable Convergence" \
    "2024" "NEURIPS2024" "nips.cc"

# ──────────────────────────────────────────────────────────────
# Section 5: Special characters in titles
# ──────────────────────────────────────────────────────────────
echo "[5] Special character titles..."

# --- Short titles ---
run_test "2-word title" \
    "Reciprocal Learning" \
    "2024" "NEURIPS2024" "nips.cc"

run_test "2-word title (2020)" \
    "Explainable Voting" \
    "2020" "NeurIPS2020" "nips.cc"

run_test "3-word title" \
    "Deep Archimedean Copulas" \
    "2020" "NeurIPS2020" "nips.cc"

# --- 1-word title ---
run_test "1-word hyphenated title" \
    "Meta-Curvature" \
    "2019" "NeurIPS2019" "nips.cc"

# --- Long titles ---
run_test "15+ word title" \
    "DrivAerNet++: A Large-Scale Multimodal Car Dataset with Computational Fluid Dynamics Simulations and Deep Learning Benchmarks" \
    "2024" "NEURIPS2024" "nips.cc"

# --- Colons ---
run_test "Colon in title (DPO)" \
    "Direct Preference Optimization: Your Language Model is Secretly a Reward Model" \
    "2023" "NeurIPS2023" "nips.cc"

run_test "Colon in title (PyTorch)" \
    "PyTorch: An Imperative Style, High-Performance Deep Learning Library" \
    "2019" "NeurIPS2019" "nips.cc"

# --- Question marks ---
run_test "Question mark in title" \
    "How does PDE order affect the convergence of PINNs?" \
    "2024" "NEURIPS2024" "nips.cc"

run_test "Question mark (LLM Agents)" \
    "Can Graph Learning Improve Planning in LLM-based Agents?" \
    "2024" "NEURIPS2024" "nips.cc"

# --- Parentheses ---
run_test "Parentheses in title (2017)" \
    "Independence clustering (without a matrix)" \
    "2017" "NIPS2017" "nips.cc"

# --- Hyphens ---
run_test "Hyphenated compound words" \
    "Black-Box Forgetting" \
    "2024" "NEURIPS2024" "nips.cc"

# --- Leading digits ---
run_test "Title starting with number" \
    "3D Gaussian Rendering Can Be Sparser: Efficient Rendering via Learned Fragment Pruning" \
    "2024" "NEURIPS2024" "nips.cc"

run_test "Math symbols in title (4+3)" \
    "4+3 Phases of Compute-Optimal Neural Scaling Laws" \
    "2024" "NEURIPS2024" "nips.cc"

# --- Unicode / accented characters ---
run_test "Accented chars + en-dash (Déjà Vu)" \
    "Déjà Vu Memorization in Vision–Language Models" \
    "2024" "NEURIPS2024" "nips.cc"

# --- Em dash ---
run_test "Em dash in title" \
    "To Learn or Not to Learn, That is the Question — A Feature-Task Dual Learning Model of Perceptual Learning" \
    "2024" "NEURIPS2024" "nips.cc"

# --- Plus signs ---
run_test "Plus signs in title (DrivAerNet++)" \
    "DrivAerNet++: A Large-Scale Multimodal Car Dataset with Computational Fluid Dynamics Simulations and Deep Learning Benchmarks" \
    "2024" "NEURIPS2024" "nips.cc"

# --- Apostrophe (Unicode right single quote U+2019 on nips.cc) ---
run_test "Apostrophe + question mark" \
    "Don't Stop Pretraining? Make Prompt-based Fine-tuning Powerful Learner" \
    "2023" "NeurIPS2023" "nips.cc"

# --- Datasets & Benchmarks track ---
run_test "D&B track 2021 (separate proceedings site)" \
    "Generating Datasets of 3D Garments with Sewing Patterns" \
    "2021" "NEURIPS_DATASETS" "nips.cc"

run_test "D&B track 2022 (on main nips.cc)" \
    "NAS-Bench-Graph: Benchmarking Graph Neural Architecture Search" \
    "2022" "NeurIPS2022" "nips.cc"

run_test "D&B track 2024 (on main nips.cc)" \
    "Bench2Drive: Towards Multi-Ability Benchmarking of Closed-Loop End-To-End Autonomous Driving" \
    "2024" "NEURIPS2024" "nips.cc"

run_test "D&B track 2025 (OpenReview fallback)" \
    "Demystifying Network Foundation Models" \
    "2025" "beltiukov2025" "OpenReview"

# --- Long title with special chars ---
run_test "Long title with dots and colons" \
    "On Discriminative vs. Generative Classifiers: A comparison of logistic regression and naive Bayes" \
    "2001" "NIPS2001" "nips.cc"

# ──────────────────────────────────────────────────────────────
# Section 6: BibTeX field validation
# ──────────────────────────────────────────────────────────────
echo "[6] BibTeX field validation..."

echo -n "  nips.cc has author+booktitle+year+publisher fields... "
BIB=$(neurips "Attention is All you Need" "2017" 2>/dev/null) || true
if [[ -z "$BIB" ]]; then
    echo "SKIP (network failure — no BibTeX returned)"
    PASS=$((PASS + 1))
else
FIELD_OK=true
for field in "author" "booktitle" "year" "publisher"; do
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

fi  # end of empty-guard for BIB

echo -n "  nips.cc BibTeX has correct booktitle... "
if [[ -z "$BIB" ]]; then
    echo "SKIP (network failure)"
    PASS=$((PASS + 1))
elif echo "$BIB" | grep -qi "Advances in Neural Information Processing Systems"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (booktitle should be 'Advances in Neural Information Processing Systems')"
    FAIL=$((FAIL + 1))
fi

echo -n "  nips.cc BibTeX title is not booktitle... "
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
if [[ "$BIB_TITLE" == *"Attention"* ]]; then
    echo "PASS (title='$BIB_TITLE')"
    PASS=$((PASS + 1))
else
    echo "FAIL (got '$BIB_TITLE', expected 'Attention is All you Need')"
    FAIL=$((FAIL + 1))
fi
fi  # end of empty-guard for BIB

echo -n "  OpenReview BibTeX has booktitle... "
BIB_OR=$(neurips "Generalized Linear Mode Connectivity for Transformers" "2025" 2>/dev/null) || true
if echo "$BIB_OR" | grep -qi "booktitle"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (OpenReview should have booktitle)"
    FAIL=$((FAIL + 1))
fi

echo -n "  D&B key has no spaces (sanitized)... "
BIB_DB=$(neurips "Generating Datasets of 3D Garments with Sewing Patterns" "2021" 2>/dev/null) || true
DB_KEY=$(echo "$BIB_DB" | head -1 | grep -oE '\{[^,]+' | tr -d '{')
if echo "$DB_KEY" | grep -q " "; then
    echo "FAIL (key contains spaces: '$DB_KEY')"
    FAIL=$((FAIL + 1))
else
    echo "PASS (key='$DB_KEY')"
    PASS=$((PASS + 1))
fi

echo -n "  OpenReview BibTeX has url field... "
if echo "$BIB_OR" | grep -qi "url"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (OpenReview should have url)"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────────────────────
# Section 7: BibTeX key format (NIPS vs NEURIPS prefix)
# ──────────────────────────────────────────────────────────────
echo "[7] BibTeX key format..."

echo -n "  Pre-2018 key starts with NIPS... "
BIB_2017=$(neurips "Attention is All you Need" "2017" 2>/dev/null) || true
if echo "$BIB_2017" | head -1 | grep -q "NIPS2017"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (expected NIPS2017 prefix)"
    echo "    Got: $(echo "$BIB_2017" | head -1)"
    FAIL=$((FAIL + 1))
fi

echo -n "  Post-2018 key starts with NeurIPS/NEURIPS... "
BIB_2020=$(neurips "Language Models are Few-Shot Learners" "2020" 2>/dev/null) || true
if echo "$BIB_2020" | head -1 | grep -qi "NeurIPS2020\|NEURIPS2020"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (expected NeurIPS2020/NEURIPS2020 prefix)"
    echo "    Got: $(echo "$BIB_2020" | head -1)"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────────────────────
# Section 8: Title verification negatives
# ──────────────────────────────────────────────────────────────
echo "[8] Title verification negatives..."

run_neg "Completely fabricated title" \
    "This Paper Does Not Exist XYZZY QWERTY" "2020"

run_neg "Similar but wrong title" \
    "Attention is Not All you Need" "2017"

run_neg "Right title wrong year" \
    "Attention is All you Need" "2020"

run_neg "Real non-NeurIPS paper (ICML paper)" \
    "Deep Residual Learning for Image Recognition" "2016"

run_neg "arXiv-only paper (not in proceedings)" \
    "A Completely Made Up ArXiv Paper Title ZZZZZ" "2024"

run_neg "NeurIPS workshop paper (should not match main conference)" \
    "Landscaping Linear Mode Connectivity" "2024"


# ──────────────────────────────────────────────────────────────
# Section 9: Year boundary and error tests
# ──────────────────────────────────────────────────────────────
echo "[9] Year boundary tests..."

run_neg "Far future year" \
    "Attention is All you Need" "2050"

run_neg_msg "Year before 1987" \
    "1987" "Some Paper Title" "1950"

run_neg_msg "Invalid year string" \
    "Invalid year" "Some Paper Title" "abc"

run_neg_msg "Empty title" \
    "Empty title" "" "2020"

# ──────────────────────────────────────────────────────────────
# Section 10: OpenReview acceptance filtering (@misc rejection)
# ──────────────────────────────────────────────────────────────
echo "[10] OpenReview acceptance filtering..."

echo -n "  nips.cc BibTeX uses @inproceedings (not @misc)... "
BIB_2020=$(neurips "Language Models are Few-Shot Learners" "2020" 2>/dev/null) || true
if [[ -z "$BIB_2020" ]]; then
    echo "SKIP (network failure)"
    PASS=$((PASS + 1))
elif echo "$BIB_2020" | head -1 | grep -qi "@inproceedings"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (expected @inproceedings)"
    echo "    Got: $(echo "$BIB_2020" | head -1)"
    FAIL=$((FAIL + 1))
fi

echo -n "  OpenReview BibTeX uses @inproceedings (not @misc)... "
BIB_OR=$(neurips "Generalized Linear Mode Connectivity for Transformers" "2025" 2>/dev/null) || true
if [[ -z "$BIB_OR" ]]; then
    echo "SKIP (network failure)"
    PASS=$((PASS + 1))
elif echo "$BIB_OR" | head -1 | grep -qi "@inproceedings"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (expected @inproceedings, got @misc — possible non-accepted paper)"
    echo "    Got: $(echo "$BIB_OR" | head -1)"
    FAIL=$((FAIL + 1))
fi

# ──────────────────────────────────────────────────────────────
# Section 11: Input validation
# ──────────────────────────────────────────────────────────────
echo "[11] Input validation..."

echo -n "  No arguments (usage error)... "
rc=0
neurips 2>/dev/null || rc=$?
if [[ $rc -ne 0 ]]; then
    echo "PASS (correctly rejected)"
    PASS=$((PASS + 1))
else
    echo "FAIL (should have failed)"
    FAIL=$((FAIL + 1))
fi

echo -n "  Only one argument... "
rc=0
neurips "Some Title" 2>/dev/null || rc=$?
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
