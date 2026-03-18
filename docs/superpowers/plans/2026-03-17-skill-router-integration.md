# Skill Router Integration & Workflow Restructuring — Implementation Plan

> **For agentic workers:** REQUIRED: Use the 3-agent execution model defined below. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate 21 categories of AI research domain skills into the research workflow via a central Skill Router, restructure phases (merge discover+triage, add discuss), and add adversarial review mechanisms.

**Architecture:** All deliverables are Claude Code skill files (`.md`). The Skill Router is a new phase module that maps paper content to domain skills. Existing bash scripts and data files are reused unchanged. The discuss phase is the largest new addition — a 9-sub-phase ideation engine with adversarial checks.

**Tech Stack:** Claude Code skills (Markdown), Bash scripts (existing), SQLite databases (existing), MCP integrations (existing)

**Spec:** `docs/superpowers/specs/2026-03-17-skill-router-integration-design.md`

---

## Execution Model: 3-Agent Quality Pipeline

Each task goes through a structured quality pipeline:

| Agent | Model | Effort | Role | Trigger |
|-------|-------|--------|------|---------|
| **Writer** | Sonnet 4.6 | medium | Writes code per plan steps. Follows spec exactly. | Each task |
| **Supervisor** | Opus 4.6 | medium | Reviews Writer's output line-by-line. Runs validation tests. Ensures each unit passes before proceeding. | After each task |
| **Module Reviewer** | Opus 4.6 | high | After units form a complete module, reviews integrated behavior: does the module work as a whole? Are cross-unit interactions correct? Does it match spec intent? | After each module boundary (marked below) |

**Flow per task:**
```
Writer implements task → Supervisor validates + tests → fix issues → next task
```

**Flow per module:**
```
All tasks in module complete → Module Reviewer checks integrated behavior → fix issues → next module
```

---

## File Map

### New files (create)

| File | Responsibility |
|------|---------------|
| `skills/research/phases/skill-router.md` | Central domain detection + skill routing |
| `skills/research/phases/discuss.md` | Deep discussion + research ideation phase |
| `skills/research/tests/test_structure.sh` | Structural validation for all skill files |

### Files to rewrite

| File | What changes |
|------|-------------|
| `skills/research/phases/discover.md` | Full rewrite: absorb triage + quick-read, add skill router + landscape summary |

### Files to modify

| File | What changes |
|------|-------------|
| `skills/research/SKILL.md` | Routing table, unified input parsing, dependencies, iron rules |
| `skills/research/phases/read.md` | Add skill router invocation + domain expert perspective |
| `skills/research/phases/write.md` | Add Triple Review Gate + Consistency Check + skill router |
| `skills/research/phases/cite.md` | Add unified input parsing reference |
| `skills/research/phases/trending.md` | Add lightweight skill router invocation |
| `.claude-plugin/marketplace.json` | Update description (remove "triage" references) |

### Files to delete

| File | Reason |
|------|--------|
| `skills/research/phases/triage.md` | Absorbed into discover |

### Files unchanged

All 18 scripts in `scripts/`, all 3 data files in `data/`, `.env`, `.env.example`.

---

## Module A: Foundation (Skill Router + Structural Tests)

### Task 1: Create structural validation test

**Files:**
- Create: `skills/research/tests/test_structure.sh`

This test validates that all skill files are internally consistent: referenced scripts exist, phase files exist, no broken references. It runs after every subsequent task.

- [ ] **Step 1: Write the validation test script**

```bash
#!/usr/bin/env bash
# test_structure.sh — Validate skill file structural integrity
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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
    ((ERRORS++))
  fi
done

# 2. Check all scripts referenced across phase files exist
echo "[2] Checking script references..."
REFERENCED_SCRIPTS=$(grep -roh 'scripts/[a-z_]*.sh' "$PHASES_DIR" "$SCRIPT_DIR/SKILL.md" 2>/dev/null | sort -u)
for script_ref in $REFERENCED_SCRIPTS; do
  script_name=$(basename "$script_ref")
  if [[ -f "$SCRIPTS_DIR/$script_name" ]]; then
    echo "  ✓ scripts/$script_name exists"
  else
    echo "  ✗ scripts/$script_name MISSING (referenced in phase files)"
    ((ERRORS++))
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
  ((ERRORS++))
else
  echo "  ✓ No /research survey references"
fi
if grep -q '/research triage' "$SCRIPT_DIR/SKILL.md" 2>/dev/null; then
  echo "  ✗ SKILL.md still references /research triage (should be removed)"
  ((ERRORS++))
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
      ((ERRORS++))
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
      ((ERRORS++))
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
      ((ERRORS++))
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
    ((ERRORS++))
  fi
done

# 9. Check routing table includes /research discuss and excludes triage.md
echo "[9] Checking routing table..."
if grep -q '/research discuss' "$SCRIPT_DIR/SKILL.md" 2>/dev/null; then
  echo "  ✓ /research discuss in routing table"
else
  echo "  ✗ /research discuss MISSING from routing table"
  ((ERRORS++))
fi
if grep -q 'triage.md' "$SCRIPT_DIR/SKILL.md" 2>/dev/null; then
  echo "  ✗ SKILL.md still references triage.md"
  ((ERRORS++))
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
```

- [ ] **Step 2: Make executable and run initial baseline**

Run: `chmod +x skills/research/tests/test_structure.sh && bash skills/research/tests/test_structure.sh`

Expected: Some checks pass (existing scripts), some skipped (skill-router.md, discuss.md not yet created). No unexpected failures on existing files.

- [ ] **Step 3: Commit**

```bash
git add skills/research/tests/test_structure.sh
git commit -m "test: add structural validation for skill files"
```

---

### Task 2: Create skill-router.md

**Files:**
- Create: `skills/research/phases/skill-router.md`

The central module. All other phases depend on this.

- [ ] **Step 1: Write skill-router.md**

Create `skills/research/phases/skill-router.md` with the complete content per spec Section 3 (3.1–3.8). Must include:

1. **Header**: Markdown document title + purpose statement
2. **Interface section**: Input parameters (`paper_metadata`, `topic_description`, `phase_type`, `user_domain_override`, `user_domain_only`) and output format (JSON with `primary` and `secondary` arrays)
3. **Detection logic**: Three-branch logic (domain-only → domain override + auto → auto-only). Include the primary/secondary heuristic (title + first 2 sentences = primary; methodology-only = secondary)
4. **Full mapping table**: All 21 categories with trigger keywords and available skills — copy exactly from spec Section 3.4
5. **Intra-category selection**: General rule (default to first skill; max 3 per category) + all examples from spec
6. **Phase-specific behavior table**: What gets invoked per phase + detail level — copy from spec Section 3.5
7. **User override section**: `--domain` (additive) and `--domain-only` (exclusive) syntax and rules
8. **Error handling table**: All 4 scenarios from spec Section 3.7
9. **Performance considerations**: Caching strategy per phase from spec Section 3.8

**Document skeleton** (Writer agent must follow this structure exactly):

```markdown
# Skill Router

Central module for mapping paper content to domain-specific AI research skills.

## Interface

### Input
[paper_metadata, topic_description, phase_type, user_domain_override, user_domain_only — per spec 3.2]

### Output
[JSON format with primary/secondary arrays — per spec 3.2]

## Detection Logic
[Three-branch logic — per spec 3.3]

## Category Mapping Table
[COPY VERBATIM from spec Section 3.4 — all 21 rows of the table, every keyword, every skill name. Do NOT paraphrase or abbreviate.]

## Intra-Category Skill Selection
[General rule + examples — per spec 3.4 bottom]

## Phase-Specific Behavior
[Table from spec 3.5]

## User Override
[--domain and --domain-only rules — per spec 3.6]

## Error Handling
[4-scenario table — per spec 3.7]

## Performance Considerations
[Caching strategy — per spec 3.8]
```

Reference: Spec Section 3 (lines 41–166)

- [ ] **Step 2: Run structural test**

Run: `bash skills/research/tests/test_structure.sh`

Expected: Check [5] passes — all 21 category names present in skill-router.md.

- [ ] **Step 3: Commit**

```bash
git add skills/research/phases/skill-router.md
git commit -m "feat: add skill router module with 21-category mapping"
```

---

### Task 3: Add unified input parsing to SKILL.md

**Files:**
- Modify: `skills/research/SKILL.md`

Add the shared input parsing logic as a new section, per spec Section 4.

- [ ] **Step 1: Add Unified Input Parsing section to SKILL.md**

Insert a new section `## Unified Input Parsing` after the `## Workspace` section in SKILL.md. Content per spec Section 4:

```markdown
## Unified Input Parsing

Phases that accept a paper identifier (discuss, read, cite) share this logic. Discover takes a topic description, not a paper identifier.

### Input Types

- **arXiv ID** (e.g., `2401.12345`): Direct lookup via `s2_match.sh` or S2 API
- **DOI** (e.g., `10.1109/...`): Direct CrossRef/S2 lookup
- **Free text** (paper title or keywords):
  1. Try `s2_match.sh "<text>"` for exact title match
  2. If no exact match: `s2_search.sh "<text>" 5` + `dblp_search.sh "<text>" 5`

### Clarify Flow

When free-text search returns multiple candidates, present each with:
- Title + authors (first 3) + year + venue
- One-sentence core contribution (from abstract)
- Quality marker (CCF/JCR tier, citation count via `venue_info.sh`)

User selects one → proceed to the requested phase.

### Domain Override Flags

All commands (except trending) support:
- `--domain <cat1,cat2>`: Additive — merge with auto-detected categories
- `--domain-only <cat1,cat2>`: Exclusive — use only these categories

Category names match the skill-router mapping table (semantic match OK).
```

- [ ] **Step 2: Verify SKILL.md is valid markdown**

Run: `head -80 skills/research/SKILL.md` — visually confirm the new section is properly placed and formatted.

- [ ] **Step 3: Commit**

```bash
git add skills/research/SKILL.md
git commit -m "feat: add unified input parsing and domain override flags to SKILL.md"
```

---

> **🔍 MODULE A REVIEW CHECKPOINT**
>
> Module Reviewer (Opus 4.6 high): Validate that:
> 1. `skill-router.md` contains all 21 categories with correct keywords matching spec
> 2. Unified input parsing in SKILL.md correctly references `s2_match.sh`, `s2_search.sh`, `dblp_search.sh`
> 3. `--domain` / `--domain-only` semantics match spec Section 3.6
> 4. Error handling covers all 4 scenarios from spec Section 3.7
> 5. Structural test passes cleanly for the foundation layer

---

## Module B: Discover Phase (Rewrite)

### Task 4: Rewrite discover.md

**Files:**
- Rewrite: `skills/research/phases/discover.md`

Absorb triage + quick-read into discover. This is the largest single-file rewrite.

- [ ] **Step 1: Back up current discover.md**

Run: `cp skills/research/phases/discover.md skills/research/phases/discover.md.bak`

- [ ] **Step 2: Write new discover.md**

Rewrite `skills/research/phases/discover.md` with the complete content per spec Section 5.1. Must include:

1. **Header**: `# Discover Phase` + updated description (broad field scan: search → triage → quick-read → landscape report)
2. **Trigger**: Updated — called via `/research discover "topic"` only (no more `/research survey`)
3. **Step 1 (Parse query)**: Same as current + add skill router invocation with `topic_description` and `phase_type: "discover"`
4. **Step 2 (Search strategy)**: NEW — invoke `research-ideation` skill (`brainstorming-research-ideas`) to generate diversified search queries from the user's topic
5. **Step 3 (Parallel search)**: Same 3-agent architecture — copy from current `discover.md` "Step 2: Parallel search" section verbatim (Agent 1: S2 with `s2_search.sh`/`s2_bulk_search.sh`, Agent 2: AlphaXiv MCP `embedding_similarity_search`/`full_text_papers_search`, Agent 3: HF MCP `paper_search`). Preserve exact bash commands and timeout policy.
6. **Step 4 (Merge)**: Same deduplication logic — copy from current `discover.md` "Step 3: Merge" section verbatim (dedup by arXiv ID, DOI, title similarity >85%, normalize to common JSON format)
7. **Step 5 (Quality evaluation)**: Same scoring formula — copy from current `discover.md` "Step 4: Quality evaluation" section verbatim. Preserve the exact composite score formula: `base_score = max(CCF, JCR, CAS)`, `weighted = IF*0.3 + citations*0.2 + year*0.1 + h_index*0.1`, `penalty = -20 if arXiv AND citations < 100`, `total = base_score + weighted + penalty`. Preserve all dimension weights table.
8. **Step 6 (Quick-read)**: NEW — absorbed from triage.md. For top N papers by score:
   - Fetch overview: AlphaXiv MCP `get_paper_content` (report mode) or `curl -s "https://alphaxiv.org/overview/{arxiv_id}.md"` or S2 abstract
   - For non-arXiv: check S2 `openAccessPdf` or resolve DOI
   - Generate per paper: one-sentence core contribution + read recommendation ("Must read" / "Worth reading" / "Skim" / "Skip")
   - Invoke matched domain skill (from step 1's router result) for domain-specific relevance assessment
9. **Step 7 (Present results)**: Updated format — combine old discover output + triage verdicts:
   ```
   1. [Must read] Title (Year) — Venue
      Authors (first 3)
      Core contribution: one sentence
      Citations: N | Quality: CCF-A / Q1 | Score: X.X
      Relevance: domain-specific assessment from skill
   ```
10. **Step 8 (Landscape summary)**: NEW — synthesize a 1-paragraph overview: key themes, dominant approaches, recent trends, notable gaps
11. **Step 9 (Save to workspace)**: Save to `discover.json` with extended schema:
    ```json
    {
      "query": "...",
      "timestamp": "...",
      "landscape_summary": "...",
      "skills_invoked": ["..."],
      "total_found": 42,
      "results": [{
        "paper_id": "...", "title": "...", "score": 85.3,
        "verdict": "must_read", "core_contribution": "...",
        "domain_assessment": "..."
      }]
    }
    ```
12. **Step 10 (Expansion options)**: Updated — remove "Ready to triage?", add "Proceed to discuss?"
    - "Want to find papers that cite [paper X]?" → `s2_citations.sh`
    - "Want to trace references of [paper X]?" → `s2_references.sh`
    - "Want recommendations based on these papers?" → `s2_recommend.sh`
    - "Ready to discuss?" → proceed to discuss phase

- [ ] **Step 3: Run structural test**

Run: `bash skills/research/tests/test_structure.sh`

Expected: All checks pass. No references to removed commands.

- [ ] **Step 4: Verify no triage references leak into discover**

Run: `grep -i "triage" skills/research/phases/discover.md`

Expected: No results (or only in historical context like "absorbed from triage").

- [ ] **Step 5: Commit**

```bash
git add skills/research/phases/discover.md
git commit -m "feat: rewrite discover phase — absorb triage + quick-read, add skill router + landscape summary"
```

- [ ] **Step 6: Remove backup**

Run: `rm skills/research/phases/discover.md.bak`

---

> **🔍 MODULE B REVIEW CHECKPOINT**
>
> Module Reviewer (Opus 4.6 high): Validate that:
> 1. All search logic from old discover.md is preserved (S2, AlphaXiv, HF agents)
> 2. All triage logic from old triage.md is absorbed (overview fetching, verdict generation)
> 3. Scoring formula is unchanged from original
> 4. Skill router is invoked correctly (with `topic_description`, not `paper_metadata`)
> 5. `research-ideation` is invoked for search strategy generation
> 6. Expansion options no longer reference triage
> 7. Workspace output includes new fields (`landscape_summary`, `verdict`, `domain_assessment`)
> 8. Quick-read section handles both arXiv and non-arXiv papers

---

## Module C: Discuss Phase (New)

### Task 5: Create discuss.md — Setup, Assumption Surfacing, Discussion Loop

**Files:**
- Create: `skills/research/phases/discuss.md`

Build the first half of the discuss phase: entry point, setup, assumption surfacing, and the core discussion loop (phases 1-3).

- [ ] **Step 1: Write discuss.md (phases 1-3)**

Create `skills/research/phases/discuss.md` with:

**Document skeleton** (Writer agent must follow this structure):

```markdown
# Discuss Phase
[description]

## Trigger
[entry commands]

## Phase 1: Setup
## Phase 2: Assumption Surfacing
## Phase 3: Discussion Loop
## Phase 4: Adversarial Novelty Check
## Phase 5: Reviewer Simulation
## Phase 6: Significance Test
## Phase 7: Simplicity Test
## Phase 8: Experiment Design
## Phase 9: Convergence Decision
## Research Brief Output Schema
## Scripts Reused
```

Content per phase:

1. **Header**: `# Discuss Phase` + description: Deep discussion, iterative ideation, open problem identification, method design
2. **Trigger**: `/research discuss` (uses current session's discover output) or `/research discuss <paper>` (starts from a specific paper, uses unified input parsing from SKILL.md)
3. **Phase 1 — Setup**:
   - Load current session's `discover.json` (if available) and any `read/*.json` analyses
   - Invoke skill router with collected paper metadata, `phase_type: "discuss"` → load all primary domain skills
   - Always invoke `research-ideation` skills: `brainstorming-research-ideas` + `creative-thinking-for-research`
   - If entering from `/research discuss <paper>`, resolve paper via unified input parsing first, then run quick discover around that paper's topic for context
4. **Phase 2 — Assumption Surfacing**:
   - Review all surveyed/read papers and list shared assumptions the field takes for granted
   - For each assumption: is it explicitly validated in the literature, or inherited convention?
   - Flag unvalidated assumptions as candidate research angles — "What if this assumption is wrong?"
   - Present to user for discussion
5. **Phase 3 — Discussion Loop** (iterative, user-driven):
   - Propose analysis perspectives infused with domain skill expertise
   - Respond to user's questions, challenges, and proposed directions
   - **Knowledge gap detection**:
     - Method/baseline mentioned but not in session → auto-trigger discover+read to fill gap
     - User questions a conclusion without comparison data → targeted read
     - Domain skill suggests related work → supplementary discover
   - **Out-of-domain search**:
     - Abstract the core problem to a general form (e.g., "signal recovery under noise" instead of "pose estimation in fog")
     - Search S2 with the abstracted query in adjacent fields
     - Present cross-domain insights and analogies
   - Continuously update research brief (findings, open problems, candidate directions, evidence)
   - Note on convergence: "Phases 4-9 trigger when user signals readiness (e.g., 'let's finalize' or 'I think we have a direction'). User can request any phase individually, skip inapplicable phases, or loop back from any phase to Phase 3."

- [ ] **Step 2: Run structural test**

Run: `bash skills/research/tests/test_structure.sh`

Expected: Check [6] — "Assumption Surfacing" and "Discussion Loop" present. Other discuss sections show as missing (expected — we add them in Task 6).

- [ ] **Step 3: Commit**

```bash
git add skills/research/phases/discuss.md
git commit -m "feat: add discuss phase — setup, assumption surfacing, discussion loop"
```

---

### Task 6: Complete discuss.md — Convergence Phases 4-9

**Files:**
- Modify: `skills/research/phases/discuss.md`

Add phases 4-9 (adversarial check through convergence) and the research brief output schema.

- [ ] **Step 1: Add phases 4-9 to discuss.md**

Append to the existing discuss.md:

6. **Phase 4 — Adversarial Novelty Check**:
   - For each proposed direction:
     - `bash scripts/s2_search.sh "<direction summary>" 10` — find closest existing work
     - `bash scripts/s2_snippet.sh "<specific method combination>"` — check if method combo exists
     - `bash scripts/s2_recommend.sh` with direction's key papers as positives — find similar work
   - Retrieve and quick-read top 5 closest existing papers
   - Present side-by-side comparison: how does the proposed idea differ from each?
   - If differentiation is insufficient → flag as "likely incremental" and suggest pivots
   - If concurrent work detected (arXiv preprint from last 6 months with >70% conceptual overlap) → warn explicitly

7. **Phase 5 — Reviewer Simulation**:
   - Generate 3-4 likely reviewer objections for the proposed direction
   - For each objection: what is the weakest claim? What baseline would they demand? What ablation is essential?
   - Frame as specific review comments: "Reviewer 2 would ask: 'Why not compare against [method X]?'"
   - Store as `anticipated_objections` in research brief with severity rating

8. **Phase 6 — Significance Test** (3 tiers):
   - Tier 1: Does this affect real systems/users? Must articulate at least one concrete failure mode with evidence
   - Tier 2: If solved, would the community approach the broader problem differently? (Not just benchmark numbers)
   - Tier 3: Is the expected improvement meaningful or marginal? Compare against current SOTA numbers from read analyses
   - Explicit flag if any tier is weak — user must acknowledge before proceeding

9. **Phase 7 — Simplicity Test**:
   - Ask user to explain the proposed idea in 2 sentences to a first-year undergrad
   - If the explanation requires jargon or is longer → suggest simplification
   - Check: is there a simpler version of this idea that captures the core insight?
   - Bias toward elegance: "The best ideas can usually be stated without jargon"

10. **Phase 8 — Experiment Design**:
    - Required baselines (from adversarial check's closest existing work)
    - Datasets to evaluate on (from read analyses — what benchmarks does the field use?)
    - Ablation studies needed (from reviewer simulation's anticipated questions)
    - Expected results table (rough estimates based on SOTA numbers + proposed improvement)
    - Compute/data requirements — does the user have what's needed?

11. **Phase 9 — Convergence Decision**:
    - If multiple candidate directions: present direction comparison matrix
      - Columns: Novelty | Feasibility | Impact | Risk | Reviewer Objection Severity
      - Each cell backed by specific evidence from analyzed papers
    - User commits to a direction
    - Categorize the chosen direction: Incremental / Solid contribution / High-impact
    - Final research brief saved to workspace

12. **Research Brief Output Schema**: Add the full `brief.json` schema from spec (lines 305-340) as documentation at the end of discuss.md. Path: `.research-workspace/sessions/{slug}/discuss/brief.json`

13. **Scripts Reused**: List all scripts used by discuss phase (from spec lines 306-311)

- [ ] **Step 2: Run structural test**

Run: `bash skills/research/tests/test_structure.sh`

Expected: Check [6] fully passes — all 8 discuss sections present.

- [ ] **Step 3: Commit**

```bash
git add skills/research/phases/discuss.md
git commit -m "feat: complete discuss phase — adversarial check, reviewer sim, significance, convergence"
```

---

> **🔍 MODULE C REVIEW CHECKPOINT**
>
> Module Reviewer (Opus 4.6 high): Validate that:
> 1. All 9 sub-phases from spec Section 5.2 are present and complete
> 2. The discussion loop correctly references skill router and research-ideation skills
> 3. Knowledge gap detection triggers the right scripts (s2_search, s2_citations, etc.)
> 4. Out-of-domain search abstracts the problem correctly (general form, not domain-specific)
> 5. Adversarial novelty check uses s2_search + s2_snippet + s2_recommend per spec
> 6. Reviewer simulation generates specific objections, not generic ones
> 7. Significance test has all 3 tiers with concrete failure mode requirement
> 8. Research brief JSON schema matches spec exactly
> 9. Convergence decision includes direction comparison matrix
> 10. Phase 3→4-9 transition note is present (user-triggered, skippable, loopable)

---

## Module D: Phase Modifications (Read + Write + Cite + Trending)

### Task 7: Modify read.md

**Files:**
- Modify: `skills/research/phases/read.md`

- [ ] **Step 1: Add skill router invocation to read.md**

Insert after Step 1 (Resolve paper identity) and before Step 2 (Fetch full paper content):

```markdown
### Step 1.5: Invoke Skill Router

After resolving the paper's identity, invoke the skill router:
- Input: paper's title, abstract (from S2 metadata), keywords, venue
- Phase type: `read`
- Apply `--domain` / `--domain-only` if user specified

The router returns primary domain skills. These are loaded and provide expert perspective during analysis (Step 5).
```

- [ ] **Step 2: Update Step 1 to reference unified input parsing**

Replace the current Step 1 content with:

```markdown
### Step 1: Resolve paper identity

Use unified input parsing (defined in SKILL.md):
- arXiv ID → direct lookup
- DOI → CrossRef/S2 lookup
- Free text → s2_match.sh exact match, then s2_search.sh + dblp_search.sh with clarify flow if multiple candidates
```

- [ ] **Step 3: Add domain expert perspective to Step 5 output**

In Step 5 (Produce structured analysis), add after the existing analysis sections:

```markdown
### Domain Expert Perspective
[Generated by the domain skills loaded in Step 1.5. Provides expert-level commentary on the paper's methodology, positioning within the field, and technical choices. Example: "From a PEFT perspective, the LoRA rank choice of 16 is conservative; recent work shows rank 4 achieves comparable results with 4x less parameters."]
```

- [ ] **Step 4: Update Step 6 workspace output**

In Step 6 (Save read results), add to the JSON schema:
```json
"skills_invoked": ["multimodal:clip", "fine-tuning:peft"]
```

- [ ] **Step 5: Run structural test**

Run: `bash skills/research/tests/test_structure.sh`

Expected: All checks pass.

- [ ] **Step 6: Commit**

```bash
git add skills/research/phases/read.md
git commit -m "feat: add skill router + domain expert perspective to read phase"
```

---

### Task 8: Modify write.md — Triple Review Gate + Consistency Check

**Files:**
- Modify: `skills/research/phases/write.md`

- [ ] **Step 1: Add skill router invocation**

Insert after Step 1 (Gather context) and before Step 2 (Invoke ml-paper-writing):

```markdown
### Step 1.5: Invoke Skill Router

Invoke the skill router with:
- Input: paper metadata from the research brief + read analyses
- Phase type: `write`
- Router returns primary domain skills for technical accuracy review

Also load the research brief from discuss phase if available:
`.research-workspace/sessions/{slug}/discuss/brief.json`

**Context source priority** (updated):
1. Research brief from discuss phase — primary framing source
2. Read analyses from workspace — detailed technical content
3. Existing `.tex` files — current draft state
4. Cite-log — verified citations
5. User's direct instructions
```

- [ ] **Step 2: Add Triple Review Gate after Step 5 (Style review)**

Insert as a new Step 5.5:

```markdown
### Step 5.5: Triple Review Gate (abstract + introduction only)

If the section being written is `abstract` or `introduction`, auto-trigger three review perspectives after the initial draft:

**Reviewer Perspective (Technical Rigor):**
- Is the motivation backed by a concrete failure mode, not an abstract gap?
- Are contributions clearly distinguished from prior work?
- Do claims align with what the experiments can demonstrate?
- Output: 2-3 specific revision suggestions pointing to concrete sentences.

**AC/SAC Perspective (Novelty & Significance):**
- Can the contribution be summarized in one sentence that a non-expert understands?
- Is this incremental or substantial? What's the delta over closest prior work?
- Is there concurrent work risk? (Check recent arXiv for similar submissions)
- Output: 2-3 specific revision suggestions pointing to concrete sentences.

**Senior Researcher Perspective (Impact & Elegance):**
- "If this research succeeds perfectly, who does something differently tomorrow?"
- Is the problem framing revealing a deeper insight, or just stating a gap?
- Is this the simplest, most elegant formulation of the contribution?
- Output: 2-3 specific revision suggestions pointing to concrete sentences.

Present all suggestions to user. User decides which to adopt. Optional re-run after revision.
```

- [ ] **Step 3: Add Consistency Check after Triple Review Gate**

Insert as Step 5.6:

```markdown
### Step 5.6: Consistency Check (method, experiments, conclusion)

If the section being written is `method`, `experiments`, or `conclusion`, run a lightweight structural cross-reference scan against existing draft sections:

- Introduction lists N contributions → does experiments have a corresponding table/figure for each?
- Method assumes specific input format → does the dataset actually provide that format?
- Abstract claims "state-of-the-art" → do results show superiority over ALL listed baselines?
- Conclusion doesn't overclaim beyond what experiments demonstrate
- Method's assumptions match experiment setup (e.g., "RGB-IR pair" input → dataset provides IR)

Flag inconsistencies for user to resolve. Do not auto-fix — the user decides which side to change.
```

- [ ] **Step 4: Run structural test**

Run: `bash skills/research/tests/test_structure.sh`

Expected: Check [7] passes — "Triple Review Gate", "Consistency Check", and "skill-router" all present in write.md.

- [ ] **Step 5: Commit**

```bash
git add skills/research/phases/write.md
git commit -m "feat: add Triple Review Gate + Consistency Check to write phase"
```

---

### Task 9: Modify cite.md + trending.md

**Files:**
- Modify: `skills/research/phases/cite.md`
- Modify: `skills/research/phases/trending.md`

- [ ] **Step 1: Update cite.md Step 1 to use unified input parsing**

Replace the current Step 1 in cite.md with:

```markdown
### Step 1: Resolve paper identity

Use unified input parsing (defined in SKILL.md):
- arXiv ID → search by ID
- DOI → use directly for CrossRef
- Free text → `s2_match.sh` exact match first, then `s2_search.sh` + `dblp_search.sh` with clarify flow if multiple candidates
```

- [ ] **Step 2: Add skill router to trending.md**

In trending.md, insert after Step 3 (Personalization filter) and before Step 4 (Present digest):

```markdown
### Step 3.5: Domain Skill Enhancement

For each paper in the High relevance tier, invoke the skill router:
- Input: paper title + summary as `paper_metadata`
- Phase type: `trending`
- Router returns top 1 primary category only (lightweight)

Use the matched domain skill to generate a one-sentence expert assessment beyond the generic relevance tier. For high-tier papers, add significance context: why this matters for the field and how it connects to the user's specific research directions.

Add to the paper presentation:
```
Domain insight: [one-sentence expert assessment from domain skill]
```
```

- [ ] **Step 3: Run structural test**

Run: `bash skills/research/tests/test_structure.sh`

Expected: All checks pass.

- [ ] **Step 4: Commit**

```bash
git add skills/research/phases/cite.md skills/research/phases/trending.md
git commit -m "feat: add unified input parsing to cite, skill router to trending"
```

---

> **🔍 MODULE D REVIEW CHECKPOINT**
>
> Module Reviewer (Opus 4.6 high): Validate that:
> 1. read.md: Skill router is invoked AFTER paper resolution but BEFORE content fetching
> 2. read.md: Domain expert perspective is a NEW section, doesn't replace existing analysis structure
> 3. read.md: Unified input parsing replaces the old resolve logic correctly
> 4. write.md: Triple Review Gate only triggers for abstract + introduction (not other sections)
> 5. write.md: Consistency Check only triggers for method, experiments, conclusion
> 6. write.md: Research brief is the PRIMARY context source (above .tex files)
> 7. write.md: All three review perspectives have specific, actionable question prompts
> 8. cite.md: Only Step 1 changed; BibTeX source chain is untouched
> 9. trending.md: Skill router is lightweight (top 1 only); only enhances high-tier papers

---

## Module E: Orchestrator Update + Cleanup

### Task 10: Update SKILL.md orchestrator

**Files:**
- Modify: `skills/research/SKILL.md`

- [ ] **Step 1: Update the routing table**

Replace the current `## Entry Point` routing table with the new one from spec Section 9:

```markdown
## Entry Point

Parse user intent from `/research <args>` and route to the appropriate phase module.

| Input pattern | Phase | Module |
|---------------|-------|--------|
| `/research discover "topic"` | discover (consolidated) | `phases/discover.md` |
| `/research discuss` | discuss (current session) | `phases/discuss.md` |
| `/research discuss <paper>` | discuss (from specific paper) | `phases/discuss.md` |
| `/research read <paper>` | read (standalone) | `phases/read.md` |
| `/research cite <paper>` | cite | `phases/cite.md` |
| `/research write <section>` | write | `phases/write.md` |
| `/research trending` | trending | `phases/trending.md` |
| Ambiguous input | Ask user to clarify | — |

`<paper>` accepts: arXiv ID, DOI, or paper title (with clarify flow if ambiguous). See Unified Input Parsing section below.

All commands support optional `--domain <categories>` or `--domain-only <categories>` flags. See Unified Input Parsing section for details.
```

- [ ] **Step 2: Add skill router to Preload section**

Update the `## Preload` section to include skill router initialization:

```markdown
## Preload

On every invocation, before doing anything else:

1. **Load high-agency skill**: Invoke `pua:high-agency` to ensure exhaustive search and retry behavior
2. **Check AlphaXiv MCP**: Test if AlphaXiv MCP tools are available. If not, operate in degraded mode (see below)
3. **Load skill router**: Read `phases/skill-router.md` for domain skill mapping. Parse any `--domain` or `--domain-only` flags from user input.
```

- [ ] **Step 3: Update Iron Rules**

Add rules 7-10 from spec Section 10 to the Iron Rules section:

```markdown
7. **Domain skill grounding** — domain skills provide expert context, but all factual claims must still trace to paper content or API responses, never to skill-generated assertions alone
8. **Adversarial before commitment** — no research direction is finalized without adversarial novelty check against existing literature
9. **Triple review for framing** — abstract and introduction must pass reviewer, AC/SAC, and senior researcher perspectives before finalization
10. **Simplicity preference** — between two approaches of similar merit, prefer the simpler one
```

- [ ] **Step 4: Update Dependencies section**

Add new dependencies:

```markdown
- `brainstorming-research-ideas` from `Orchestra-Research AI-Research-SKILLs` — search strategy and ideation
- `creative-thinking-for-research` from `Orchestra-Research AI-Research-SKILLs` — cognitive frameworks for novel ideas
- All 21 domain skill categories from `Orchestra-Research AI-Research-SKILLs` — invoked via skill router (resolved through Claude Code's Skill tool)
```

- [ ] **Step 5: Update SKILL.md header and frontmatter**

Update line 1 description (frontmatter) from "discover, triage, read, cite, write, trending" to "discover, discuss, read, cite, write, trending".

Update the `# Research Skill` header text similarly — replace any mention of "triage" with "discuss".

- [ ] **Step 6: Update Degraded Mode section**

In `## Degraded Mode`, remove the Triage bullet (`- **Triage**: ...`). The triage fallback (curl alphaxiv overview) is now part of Discover's quick-read step. Update:

```markdown
## Degraded Mode

If AlphaXiv MCP is unavailable:
- **Discover**: S2 + HF agents only (2 of 3); quick-read uses S2 abstract instead of AlphaXiv overview
- **Discuss**: Knowledge gap filling uses S2 search + arXiv PDF instead of AlphaXiv content
- **Read**: `curl -s "https://alphaxiv.org/abs/{ID}.md"`, then arXiv PDF
- **Trending**: HF daily papers only, AlphaXiv source skipped
```

- [ ] **Step 7: Update Workspace section**

Add the new `discuss/` subdirectory to the `## Workspace` section:

```markdown
Each survey creates a session: `.research-workspace/sessions/{topic-slug}-{date}/`
Contents:
- `discover.json` — search results with verdicts + landscape summary
- `discuss/brief.json` — research brief from discuss phase
- `read/{paper_id}.json` — structured paper analyses
- `cite/{paper_id}.bib` — verified BibTeX entries
- `cite/cite-log.json` — citation metadata and sources
```

- [ ] **Step 8: Update Installation prompt**

Update the installation prompt to mention the full Orchestra-Research AI-Research-SKILLs dependency:

```markdown
2. Install plugins:
   - tanwei/pua (provides high-agency, pua-en skills)
   - Orchestra-Research AI-Research-SKILLs (provides ml-paper-writing, brainstorming-research-ideas, creative-thinking-for-research, and 21 domain skill categories)
   - humanizer skill
```

- [ ] **Step 9: Run structural test**

Run: `bash skills/research/tests/test_structure.sh`

Expected: All checks pass including checks [4], [8], [9] — no removed command references, input parsing scripts referenced, routing table correct.

- [ ] **Step 10: Commit**

```bash
git add skills/research/SKILL.md
git commit -m "feat: update orchestrator — new routing table, skill router preload, iron rules 7-10, degraded mode, workspace"
```

---

### Task 11: Cleanup — delete triage.md, update marketplace.json

**Files:**
- Delete: `skills/research/phases/triage.md`
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Delete triage.md**

Run: `rm skills/research/phases/triage.md`

- [ ] **Step 2: Update marketplace.json description**

In `.claude-plugin/marketplace.json`, update the description to reflect the new architecture. Replace any mention of "triage" with the updated workflow:

Old: references to "paper triage" or similar
New: reflect discover (consolidated scan), discuss (deep ideation), read, cite, write, trending

- [ ] **Step 3: Run structural test**

Run: `bash skills/research/tests/test_structure.sh`

Expected: All checks pass. Check [3] confirms triage.md is removed. Check [4] confirms no stale references.

- [ ] **Step 4: Run ALL existing tests**

Run: `bash skills/research/tests/run_all_tests.sh`

Expected: All existing tests pass (they test scripts, not phase files, so should be unaffected).

- [ ] **Step 5: Commit**

```bash
git rm skills/research/phases/triage.md
git add .claude-plugin/marketplace.json
git commit -m "chore: remove triage.md (absorbed into discover), update marketplace description"
```

---

> **🔍 MODULE E REVIEW CHECKPOINT**
>
> Module Reviewer (Opus 4.6 high): Validate that:
> 1. SKILL.md routing table matches spec Section 9 exactly
> 2. No references to `/research survey` or `/research triage` remain **anywhere** in the codebase (grep the entire repo)
> 3. Iron rules 7-10 are appended correctly after existing rules 1-6
> 4. Dependencies list includes all new skills
> 5. triage.md is deleted
> 6. marketplace.json is updated
> 7. All existing tests still pass
> 8. Unified input parsing section is properly placed and referenced by the routing table
> 9. SKILL.md frontmatter and header text reference "discover, discuss, read, cite, write, trending" (not triage)
> 10. Degraded Mode section references Discover and Discuss (not Triage)
> 11. Workspace section documents the `discuss/` subdirectory
> 12. Installation prompt mentions full Orchestra-Research AI-Research-SKILLs dependency

---

## Module F: Final Integration Validation

### Task 12: Full integration validation

- [ ] **Step 1: Run structural test one final time**

Run: `bash skills/research/tests/test_structure.sh`

Expected: All checks pass with zero errors.

- [ ] **Step 2: Run all existing tests**

Run: `bash skills/research/tests/run_all_tests.sh`

Expected: All pass — script-level tests are unaffected by phase file changes.

- [ ] **Step 3: Cross-reference check — verify all spec requirements are implemented**

Manually verify against spec:

| Spec Section | Requirement | File | Status |
|-------------|-------------|------|--------|
| 3.1-3.8 | Skill Router with 21 categories, error handling, performance | `phases/skill-router.md` | |
| 4 | Unified Input Parsing in SKILL.md | `SKILL.md` | |
| 5.1 | Discover = search + triage + quick-read + landscape | `phases/discover.md` | |
| 5.2 | Discuss with 9 sub-phases + research brief | `phases/discuss.md` | |
| 5.3 | Read with skill router + domain expert perspective | `phases/read.md` | |
| 5.4 | Write with Triple Review Gate + Consistency Check | `phases/write.md` | |
| 5.5 | Cite with unified input parsing | `phases/cite.md` | |
| 5.6 | Trending with lightweight skill router | `phases/trending.md` | |
| 6 | triage.md deleted | — | |
| 9 | Updated routing table | `SKILL.md` | |
| 10 | Iron rules 7-10 | `SKILL.md` | |

- [ ] **Step 4: Verify workspace schema compatibility**

Check that discover.md's output schema includes the new fields:
- `landscape_summary`
- `verdict` per paper
- `core_contribution` per paper
- `domain_assessment` per paper
- `skills_invoked`

Check that discuss.md's output schema matches spec (lines 305-340).

- [ ] **Step 5: Verify backward compatibility of discover.json schema**

The new discover.json schema must be a strict superset of the old schema — new fields added, no old fields removed. Verify:
- Old fields preserved: `query`, `timestamp`, `total_found`, `results[]` with `paper_id`, `title`, `score`, `year`, `venue`, `citations`, `doi`, `arxiv_id`, `authors`, `source`, `found_in`
- New fields added: `landscape_summary`, `skills_invoked`, `results[].verdict`, `results[].core_contribution`, `results[].domain_assessment`
- No old fields renamed or removed

- [ ] **Step 6: Final commit (if any fixes were needed)**

```bash
git add -A
git commit -m "fix: integration validation fixes"
```

---

> **🔍 MODULE F FINAL REVIEW**
>
> Module Reviewer (Opus 4.6 high): End-to-end validation:
> 1. Read every phase file in order: SKILL.md → skill-router.md → discover.md → discuss.md → read.md → write.md → cite.md → trending.md
> 2. Trace a complete user workflow: `/research discover "pose estimation in fog"` → `/research discuss` → `/research write abstract`
> 3. Verify data flows: discover.json → discuss loads it → brief.json → write uses it as primary context
> 4. Verify skill router is invoked in every phase with correct phase_type
> 5. Verify no orphaned references (scripts, phases, commands)
> 6. Verify iron rules 7-10 are enforceable by the phase designs
> 7. Sign off or report blocking issues

---

## Summary

| Module | Tasks | New/Modified Files | Key Deliverable |
|--------|-------|-------------------|-----------------|
| A: Foundation | 1-3 | skill-router.md, SKILL.md (input parsing), test_structure.sh | Skill routing + validation infra |
| B: Discover | 4 | discover.md (rewrite) | Consolidated scan phase |
| C: Discuss | 5-6 | discuss.md (new) | 9-phase ideation engine |
| D: Phase Mods | 7-9 | read.md, write.md, cite.md, trending.md | Domain injection + review gates |
| E: Orchestrator | 10-11 | SKILL.md, marketplace.json, -triage.md | Updated routing + cleanup |
| F: Validation | 12 | — | Integration sign-off |

**Total**: 12 tasks, 6 module review checkpoints, ~10 commits.
