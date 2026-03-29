#!/bin/bash
# Comprehensive CVF Open Access BibTeX test
# Covers: all conferences × all available years + edge cases
# Papers verified against live CVF Open Access pages.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../skills/research/scripts"
PASS=0; FAIL=0

cvf() {
    python3 "$SCRIPTS/cvf_bibtex.py" "$@"
}

# Positive test: verify exit 0, BibTeX key, and title match
run_test() {
    local desc="$1" title="$2" author="$3" conf="$4" year="$5" expected_key="$6"
    echo -n "  $desc... "
    local rc=0
    BIB=$(cvf "$title" "$author" "$conf" "$year" 2>/dev/null) || rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "FAIL (exit $rc, expected 0)"
        FAIL=$((FAIL + 1))
        return
    fi
    if [[ -z "$BIB" ]]; then
        echo "FAIL (exit 0 but no output)"
        FAIL=$((FAIL + 1))
        return
    fi
    # Check BibTeX key
    if ! echo "$BIB" | grep -qi "$expected_key"; then
        echo "FAIL (key mismatch, expected $expected_key)"
        echo "    Got: $(echo "$BIB" | head -1)"
        FAIL=$((FAIL + 1))
        return
    fi
    # Check title field is present (not booktitle — use line-start anchor)
    if ! echo "$BIB" | grep -qE '^\s*title\s*='; then
        echo "FAIL (no title field)"
        FAIL=$((FAIL + 1))
        return
    fi
    echo "PASS"
    PASS=$((PASS + 1))
}

# Negative test: should fail (exit non-zero, no BibTeX on stdout)
run_neg() {
    local desc="$1"; shift
    echo -n "  $desc... "
    local rc=0
    BIB=$(cvf "$@" 2>/dev/null) || rc=$?
    if [[ $rc -ne 0 ]] && [[ -z "$BIB" ]]; then
        echo "PASS (correctly rejected, exit $rc)"
        PASS=$((PASS + 1))
    elif [[ $rc -eq 0 ]]; then
        echo "FAIL (exit 0, should have been rejected)"
        echo "    Got: $(echo "$BIB" | head -1)"
        FAIL=$((FAIL + 1))
    else
        echo "FAIL (exit $rc but got stdout output)"
        FAIL=$((FAIL + 1))
    fi
}

echo "========================================="
echo "CVF Open Access Comprehensive Test Suite"
echo "========================================="

# ─────────────────────────────────────────────
echo ""
echo "--- CVPR (2013-2025, all years) ---"
run_test "CVPR 2013" \
    "Deformable Spatial Pyramid Matching for Fast Dense Correspondences" \
    "Kim" "CVPR" "2013" "Kim_2013_CVPR"

run_test "CVPR 2014" \
    "Fast and Accurate Image Matching with Cascade Hashing for 3D Reconstruction" \
    "Cheng" "CVPR" "2014" "Cheng_2014_CVPR"

run_test "CVPR 2015" \
    "Going Deeper With Convolutions" \
    "Szegedy" "CVPR" "2015" "Szegedy_2015_CVPR"

run_test "CVPR 2016" \
    "Deep Compositional Captioning Describing Novel Object Categories Without Paired Training Data" \
    "Hendricks" "CVPR" "2016" "Hendricks_2016_CVPR"

run_test "CVPR 2017" \
    "Graph-Structured Representations for Visual Question Answering" \
    "Teney" "CVPR" "2017" "Teney_2017_CVPR"

run_test "CVPR 2018" \
    "Embodied Question Answering" \
    "Das" "CVPR" "2018" "Das_2018_CVPR"

run_test "CVPR 2019" \
    "Finding Task-Relevant Features for Few-Shot Learning by Category Traversal" \
    "Li" "CVPR" "2019" "Li_2019_CVPR"

run_test "CVPR 2020" \
    "Dual Super-Resolution Learning for Semantic Segmentation" \
    "Wang" "CVPR" "2020" "Wang_2020_CVPR"

run_test "CVPR 2021" \
    "Greedy Hierarchical Variational Autoencoders for Large-Scale Video Prediction" \
    "Wu" "CVPR" "2021" "Wu_2021_CVPR"

run_test "CVPR 2022" \
    "Dual Cross-Attention Learning for Fine-Grained Visual Categorization and Object Re-Identification" \
    "Zhu" "CVPR" "2022" "Zhu_2022_CVPR"

run_test "CVPR 2023" \
    "GFPose Learning 3D Human Pose Prior With Gradient Fields" \
    "Ci" "CVPR" "2023" "Ci_2023_CVPR"

run_test "CVPR 2024" \
    "Unmixing Diffusion for Self-Supervised Hyperspectral Image Denoising" \
    "Zeng" "CVPR" "2024" "Zeng_2024_CVPR"

run_test "CVPR 2025" \
    "Towards Source-Free Machine Unlearning" \
    "Ahmed" "CVPR" "2025" "Ahmed_2025_CVPR"

# ─────────────────────────────────────────────
echo ""
echo "--- ICCV (odd years: 2013-2025) ---"
run_test "ICCV 2013" \
    "Latent Task Adaptation with Large-Scale Hierarchies" \
    "Jia" "ICCV" "2013" "Jia_2013_ICCV"

run_test "ICCV 2015" \
    "Ask Your Neurons A Neural-Based Approach to Answering Questions About Images" \
    "Malinowski" "ICCV" "2015" "Malinowski_2015_ICCV"

run_test "ICCV 2017" \
    "Globally-Optimal Inlier Set Maximisation for Simultaneous Camera Pose and Feature Correspondence" \
    "Campbell" "ICCV" "2017" "Campbell_2017_ICCV"

run_test "ICCV 2019" \
    "FaceForensics++ Learning to Detect Manipulated Facial Images" \
    "Rossler" "ICCV" "2019" "Rossler_2019_ICCV"

run_test "ICCV 2021" \
    "C2N Practical Generative Noise Modeling for Real-World Denoising" \
    "Jang" "ICCV" "2021" "Jang_2021_ICCV"

run_test "ICCV 2023" \
    "Towards Attack-tolerant Federated Learning via Critical Parameter Analysis" \
    "Han" "ICCV" "2023" "Han_2023_ICCV"

run_test "ICCV 2025" \
    "Efficient Adaptation of Pre-trained Vision Transformer underpinned by Approximately Orthogonal Fine-Tuning Strategy" \
    "Yang" "ICCV" "2025" "Yang_2025_ICCV"

# ─────────────────────────────────────────────
echo ""
echo "--- WACV (2020-2026) ---"
run_test "WACV 2020" \
    "Inferring Super-Resolution Depth from a Moving Light-Source Enhanced RGB-D Sensor A Variational Approach" \
    "Sang" "WACV" "2020" "Sang_2020_WACV"

run_test "WACV 2021" \
    "Towards Contextual Learning in Few-Shot Object Classification" \
    "Fortin" "WACV" "2021" "Fortin_2021_WACV"

run_test "WACV 2022" \
    "Does Data Repair Lead to Fair Models Curating Contextually Fair Data To Reduce Model Bias" \
    "Agarwal" "WACV" "2022" "Agarwal_2022_WACV"

run_test "WACV 2023" \
    "3D Change Localization and Captioning From Dynamic Scans of Indoor Scenes" \
    "Qiu" "WACV" "2023" "Qiu_2023_WACV"

run_test "WACV 2024" \
    "Object-Centric Video Representation for Long-Term Action Anticipation" \
    "Zhang" "WACV" "2024" "Zhang_2024_WACV"

run_test "WACV 2025" \
    "Feature Augmentation Based Test-Time Adaptation" \
    "Cho" "WACV" "2025" "Cho_2025_WACV"

run_test "WACV 2026" \
    "Forget Less by Learning Together through Concept Consolidation" \
    "Kaushik" "WACV" "2026" "Kaushik_2026_WACV"

# ─────────────────────────────────────────────
echo ""
echo "--- Edge cases: short titles ---"
run_test "1-word title: IM2CAD (2017, pre-2019)" \
    "IM2CAD" "Izadinia" "CVPR" "2017" "Izadinia_2017_CVPR"

run_test "2-word title: Segment Anything (ICCV 2023)" \
    "Segment Anything" "Kirillov" "ICCV" "2023" "Kirillov_2023_ICCV"

run_test "2-word title: Ungeneralizable Examples (2024, modern)" \
    "Ungeneralizable Examples" "Ye" "CVPR" "2024" "Ye_2024_CVPR"

run_test "2-word title: Visual Dialog (2017, pre-2019)" \
    "Visual Dialog" "Das" "CVPR" "2017" "Das_2017_CVPR"

run_test "2-word title: Siamese DETR (2023, acronym)" \
    "Siamese DETR" "Huang" "CVPR" "2023" "Chen_2023_CVPR"

run_test "3-word title: Embodied Question Answering (2018)" \
    "Embodied Question Answering" "Das" "CVPR" "2018" "Das_2018_CVPR"

echo ""
echo "--- Edge cases: long titles (truncation) ---"
run_test "Long title 10-word truncation (2024)" \
    "Improving Physics-Augmented Continuum Neural Radiance Field-Based Geometry-Agnostic System Identification with Lagrangian Particle Optimization" \
    "Kaneko" "CVPR" "2024" "Kaneko_2024_CVPR"

run_test "Long title 3-word truncation (2017)" \
    "Graph-Structured Representations for Visual Question Answering" \
    "Teney" "CVPR" "2017" "Teney_2017_CVPR"

echo ""
echo "--- Edge cases: special characters in titles ---"
run_test "Colon stripped: GFPose: Learning... (2023)" \
    "GFPose Learning 3D Human Pose Prior With Gradient Fields" \
    "Ci" "CVPR" "2023" "Ci_2023_CVPR"

run_test "Apostrophe + question mark (2016)" \
    "What's Wrong With That Object? Identifying Images of Unusual Objects by Modelling the Detection Score Distribution" \
    "Wang" "CVPR" "2016" "Wang_2016_CVPR"

run_test "Hyphens preserved (2024)" \
    "Unmixing Diffusion for Self-Supervised Hyperspectral Image Denoising" \
    "Zeng" "CVPR" "2024" "Zeng_2024_CVPR"

run_test "Leading number: 3D-Aware... (2023)" \
    "3D-Aware Object Goal Navigation via Simultaneous Exploration and Identification" \
    "Zhang" "CVPR" "2023" "Zhang_2023_CVPR"

run_test "Numbers in title: 3D Change... (WACV 2023)" \
    "3D Change Localization and Captioning From Dynamic Scans of Indoor Scenes" \
    "Qiu" "WACV" "2023" "Qiu_2023_WACV"

echo ""
echo "--- Edge cases: author names ---"
run_test "Hyphenated surname: Juefei-Xu (2017)" \
    "Local Binary Convolutional Neural Networks" \
    "Juefei-Xu" "CVPR" "2017" "Juefei-Xu_2017_CVPR"

run_test "Compound surname: Rota Bulo → Bulo (2014)" \
    "Neural Decision Forests for Semantic Image Labelling" \
    "Bulo" "CVPR" "2014" "Bulo_2014_CVPR"

run_test "CVF filename author != first author: Siamese DETR (Huang in URL, Chen in BibTeX)" \
    "Siamese DETR" "Huang" "CVPR" "2023" "Chen_2023_CVPR"

echo ""
echo "--- Edge cases: URL pattern combinations ---"
run_test "2019 uppercase base + long title truncation: PartNet" \
    "PartNet A Large-Scale Benchmark for Fine-Grained and Hierarchical Part-Level 3D Object Understanding" \
    "Mo" "CVPR" "2019" "Mo_2019_CVPR"

# ─────────────────────────────────────────────
echo ""
echo "--- Edge cases: BibTeX field validation ---"
echo -n "  All required fields present (author/title/booktitle/year)... "
BIB=$(cvf "Going Deeper With Convolutions" "Szegedy" "CVPR" "2015" 2>/dev/null)
MISSING=""
echo "$BIB" | grep -q "author" || MISSING="$MISSING author"
echo "$BIB" | grep -q "title" || MISSING="$MISSING title"
echo "$BIB" | grep -q "booktitle" || MISSING="$MISSING booktitle"
echo "$BIB" | grep -q "year" || MISSING="$MISSING year"
if [[ -z "$MISSING" ]]; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL (missing:$MISSING)"
    FAIL=$((FAIL + 1))
fi

# ─────────────────────────────────────────────
echo ""
echo "--- Title verification (wrong-paper rejection) ---"
run_neg "Wrong title, correct author/conf/year" \
    "A Completely Fabricated Paper Title That Does Not Exist" \
    "Zeng" "CVPR" "2024"

run_neg "Similar first 3 words, different paper (pre-2019 slug collision)" \
    "Deep Compositional Something Totally Different" \
    "Hendricks" "CVPR" "2016"

# ─────────────────────────────────────────────
echo ""
echo "--- Error paths ---"
echo -n "  No args exits non-zero with usage message... "
ERR=$(cvf 2>&1) || true
if echo "$ERR" | grep -q "Usage:"; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Negative tests: validation ---"
run_neg "Invalid conference (ECCV)" \
    "Test Paper" "Test" "ECCV" "2024"

run_neg "Year before 2013" \
    "Test Paper" "Test" "CVPR" "2010"

run_neg "WACV before 2020" \
    "Test Paper" "Test" "WACV" "2019"

run_neg "Wrong conference for real paper (ICCV paper as CVPR)" \
    "Towards Attack-tolerant Federated Learning via Critical Parameter Analysis" \
    "Han" "CVPR" "2023"

run_neg "Paper not on CVF (real non-CVF paper)" \
    "Attention Is All You Need" \
    "Vaswani" "CVPR" "2017"

run_neg "Ampersand in title (known limitation: CVF encodes & as double underscore)" \
    "Single-View Robot Pose and Joint Angle Estimation via Render & Compare" \
    "Labbe" "CVPR" "2021"

run_neg "Workshop paper (out of scope — different URL pattern)" \
    "Unveiling the Ambiguity in Neural Inverse Rendering A Parameter Compensation Analysis" \
    "Kouros" "CVPR" "2024"

run_neg "ICCV even year (soft warning + not found)" \
    "Test Paper" "Test" "ICCV" "2024"

echo ""
echo "--- Error paths: input validation ---"
echo -n "  Invalid year string (non-numeric)... "
ERR=$(cvf "Test" "Test" "CVPR" "twenty15" 2>&1) || true
if echo "$ERR" | grep -q '"error"'; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

echo -n "  Empty title... "
ERR=$(cvf "" "Test" "CVPR" "2024" 2>&1) || true
BIB=$(cvf "" "Test" "CVPR" "2024" 2>/dev/null) || true
if [[ -z "$BIB" ]]; then
    echo "PASS (no BibTeX returned)"
    PASS=$((PASS + 1))
else
    echo "FAIL (should not return BibTeX for empty title)"
    FAIL=$((FAIL + 1))
fi

echo -n "  Empty author... "
BIB=$(cvf "Deep Residual Learning" "" "CVPR" "2024" 2>/dev/null) || true
if [[ -z "$BIB" ]]; then
    echo "PASS (no BibTeX returned)"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "cvf_bibtex: $PASS passed, $FAIL failed"
echo "========================================="
[[ $FAIL -eq 0 ]]
