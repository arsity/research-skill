#!/usr/bin/env bash
# test_structure.sh — Validate skill file structural integrity
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../skills/research" && pwd)"
PHASES_DIR="$SCRIPT_DIR/phases"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
ERRORS=0

echo "=== Structural Validation ==="

# 1. Check all phase files referenced in SKILL.md exist
echo "[1] Checking phase file references in SKILL.md..."
for phase in discover discuss read cite write trending skill-router; do
  if [[ -f "$PHASES_DIR/$phase.md" ]]; then
    echo "  ✓ phases/$phase.md exists"
  else
    echo "  ✗ phases/$phase.md MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done

# 2. Check all scripts referenced across phase files exist
echo "[2] Checking script references..."
REFERENCED_SCRIPTS=$(grep -roEh 'scripts/[a-z_]+\.(sh|py)' "$PHASES_DIR" "$SCRIPT_DIR/SKILL.md" 2>/dev/null | sort -u)
for script_ref in $REFERENCED_SCRIPTS; do
  script_name=$(basename "$script_ref")
  if [[ -f "$SCRIPTS_DIR/$script_name" ]]; then
    echo "  ✓ scripts/$script_name exists"
  else
    echo "  ✗ scripts/$script_name MISSING (referenced in phase files)"
    ERRORS=$((ERRORS + 1))
  fi
done

# 3. Check triage.md is removed (post-migration)
echo "[3] Checking migration status..."
if [[ -f "$PHASES_DIR/triage.md" ]]; then
  echo "  ⚠ phases/triage.md still exists (should be deleted after migration)"
else
  echo "  ✓ phases/triage.md removed"
fi

# 4. Check SKILL.md does not reference removed commands
echo "[4] Checking for removed command references..."
if grep -q '/research survey' "$SCRIPT_DIR/SKILL.md" 2>/dev/null; then
  echo "  ✗ SKILL.md still references /research survey (should be removed)"
  ERRORS=$((ERRORS + 1))
else
  echo "  ✓ No /research survey references"
fi
if grep -q '/research triage' "$SCRIPT_DIR/SKILL.md" 2>/dev/null; then
  echo "  ✗ SKILL.md still references /research triage (should be removed)"
  ERRORS=$((ERRORS + 1))
else
  echo "  ✓ No /research triage references"
fi

# 5. Check skill-router.md contains all 21 category names
echo "[5] Checking skill-router category coverage..."
if [[ -f "$PHASES_DIR/skill-router.md" ]]; then
  EXPECTED_CATEGORIES=(
    "Model-Architecture" "Tokenization" "Fine-Tuning"
    "Mechanistic-Interpretability" "Data-Processing" "Post-Training"
    "Safety-Alignment" "Distributed-Training" "Infrastructure"
    "Optimization" "Evaluation" "Inference-Serving" "MLOps"
    "Agents" "RAG" "Prompt-Engineering" "Observability"
    "Multimodal" "Emerging-Techniques" "ML-Paper-Writing" "Research-Ideation"
  )
  for cat in "${EXPECTED_CATEGORIES[@]}"; do
    if grep -q "$cat" "$PHASES_DIR/skill-router.md"; then
      echo "  ✓ Category '$cat' present"
    else
      echo "  ✗ Category '$cat' MISSING from skill-router.md"
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  echo "  ⚠ skill-router.md not yet created (skipping)"
fi

# 6. Check discuss.md exists and has required sections
echo "[6] Checking discuss.md structure..."
if [[ -f "$PHASES_DIR/discuss.md" ]]; then
  for section in "Assumption Surfacing" "Discussion Loop" "Adversarial Novelty Check" \
                 "Reviewer Simulation" "Significance Test" "Simplicity Test" \
                 "Experiment Design" "Convergence Decision"; do
    if grep -q "$section" "$PHASES_DIR/discuss.md"; then
      echo "  ✓ Section '$section' present"
    else
      echo "  ✗ Section '$section' MISSING from discuss.md"
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  echo "  ⚠ discuss.md not yet created (skipping)"
fi

# 7. Check write.md has Triple Review Gate and Consistency Check
echo "[7] Checking write.md enhancements..."
if [[ -f "$PHASES_DIR/write.md" ]]; then
  for feature in "Triple Review Gate" "Consistency Check" "skill-router"; do
    if grep -qi "$feature" "$PHASES_DIR/write.md"; then
      echo "  ✓ '$feature' present in write.md"
    else
      echo "  ✗ '$feature' MISSING from write.md"
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  echo "  ⚠ write.md not found"
fi

# 8. Check unified input parsing in SKILL.md references correct scripts
echo "[8] Checking unified input parsing in SKILL.md..."
for script in "s2_match.sh" "s2_search.sh" "dblp_search.sh"; do
  if grep -q "$script" "$SCRIPT_DIR/SKILL.md" 2>/dev/null; then
    echo "  ✓ $script referenced in SKILL.md"
  else
    echo "  ✗ $script MISSING from SKILL.md unified input parsing"
    ERRORS=$((ERRORS + 1))
  fi
done

# 9. Check routing table includes /research discuss and excludes triage.md
echo "[9] Checking routing table..."
if grep -q '/research discuss' "$SCRIPT_DIR/SKILL.md" 2>/dev/null; then
  echo "  ✓ /research discuss in routing table"
else
  echo "  ✗ /research discuss MISSING from routing table"
  ERRORS=$((ERRORS + 1))
fi
if grep -q 'triage.md' "$SCRIPT_DIR/SKILL.md" 2>/dev/null; then
  echo "  ✗ SKILL.md still references triage.md"
  ERRORS=$((ERRORS + 1))
else
  echo "  ✓ No triage.md references in SKILL.md"
fi

# Summary
echo ""
echo "=== Results ==="
if [[ $ERRORS -eq 0 ]]; then
  echo "✓ All checks passed"
  exit 0
else
  echo "✗ $ERRORS error(s) found"
  exit 1
fi
