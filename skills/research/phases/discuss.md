# Discuss Phase

Deep discussion, iterative ideation, open problem identification, method design.

## Trigger

- `/research discuss` — uses current session's discover output as starting context
- `/research discuss <paper>` — starts from a specific paper (uses unified input parsing from SKILL.md)

## Phase 1: Setup

1. Load current session's `discover.json` (if available) and any `read/*.json` analyses from workspace
2. Invoke skill router with collected paper metadata, `phase_type: "discuss"` → load all primary domain skills
3. Always invoke `research-ideation` skills: `brainstorming-research-ideas` + `creative-thinking-for-research`
4. If entering from `/research discuss <paper>`:
   - Resolve paper via unified input parsing first
   - Run quick discover around that paper's topic for context

## Phase 2: Assumption Surfacing

Review all surveyed/read papers and list shared assumptions the field takes for granted.

For each assumption:
- Is it explicitly validated in the literature, or inherited convention?
- Has anyone tested what happens when this assumption is violated?

Flag unvalidated assumptions as candidate research angles — "What if this assumption is wrong?"

Present to user for discussion before proceeding.

## Phase 3: Discussion Loop

Iterative, user-driven discussion. This is the core of the discuss phase.

**Analysis perspectives**: Propose analysis perspectives infused with domain skill expertise. Respond to user's questions, challenges, and proposed directions.

**Knowledge gap detection**:
- Method/baseline mentioned but not in current session → auto-trigger:
  - `bash scripts/s2_search.sh "<method>" 5` to find the paper
  - Quick-read the found paper to fill the gap
- User questions a conclusion without comparison data → targeted read of the comparison paper
- Domain skill suggests related work → supplementary discover with `s2_search.sh`

**AlphaXiv degraded mode**: If AlphaXiv MCP is unavailable, knowledge gap filling uses S2 search + arXiv PDF instead of AlphaXiv content for quick-reads of newly discovered papers.

**Out-of-domain search**:
- Abstract the core problem to a general form (e.g., "signal recovery under noise" instead of "pose estimation in fog")
- `bash scripts/s2_search.sh "<abstracted query>" 10` in adjacent fields
- Present cross-domain insights and analogies

**Continuous updates**: Throughout the discussion, continuously update the research brief with findings, open problems, candidate directions, and evidence.

**Transition note**: Phases 4-9 trigger when user signals readiness (e.g., "let's finalize" or "I think we have a direction"). User can request any phase individually (e.g., "run adversarial check"), skip inapplicable phases (e.g., skip Experiment Design for theoretical work), or loop back from any phase to Phase 3 for further discussion.

## Phase 4: Adversarial Novelty Check

For each proposed research direction:

1. **Literature search**:
   - `bash scripts/s2_search.sh "<direction summary>" 10` — find closest existing work
   - `bash scripts/s2_snippet.sh "<specific method combination>"` — check if method combo exists
   - `bash scripts/s2_recommend.sh` with direction's key papers as positives — find similar work

2. **Comparison**: Retrieve and quick-read top 5 closest existing papers. Present side-by-side comparison:
   - What is the proposed idea?
   - What does each existing paper do?
   - How does the proposed idea differ?

3. **Verdict**:
   - If differentiation is insufficient → flag as "likely incremental" and suggest pivots
   - If concurrent work detected (arXiv preprint from last 6 months with >70% conceptual overlap) → warn explicitly
   - If clearly novel → proceed with confidence

## Phase 5: Reviewer Simulation

Generate 3-4 likely reviewer objections for the proposed direction:

For each objection:
- What is the weakest claim in the current framing?
- What baseline would a reviewer demand? ("Why not compare against [method X]?")
- What ablation is essential to prove the contribution?
- Severity rating: High / Medium / Low

Frame as specific review comments:
- "Reviewer 2 would ask: 'Why not compare against [method X]? The improvement over [method Y] alone is not convincing.'"
- "Reviewer 3 would note: 'The claim about [Z] is not supported by the experiments in Table 2.'"

Store as `anticipated_objections` in the research brief with severity ratings and preemptive responses.

## Phase 6: Significance Test

Three-tier assessment:

**Tier 1 — Real-world impact**: Does this affect real systems or users?
- Must articulate at least one concrete failure mode with evidence
- Example: "Current pose estimation fails when fog density exceeds X, causing autonomous driving system to lose tracking"
- If no concrete failure mode → flag as weak

**Tier 2 — Community impact**: If solved, would the community approach the broader problem differently?
- Not just benchmark improvement — would this change how people think about the problem?
- Example: "Proving that infrared features are sufficient for nighttime pose estimation would eliminate the need for paired RGB-IR training data"

**Tier 3 — Improvement magnitude**: Is the expected improvement meaningful or marginal?
- Compare against current SOTA numbers from read analyses
- "Expected 2% improvement on metric X" vs "Expected 15% improvement on metric X"
- Factor in: is the metric saturated? Is the benchmark too easy?

Explicit flag if any tier is weak — user must acknowledge before proceeding.

## Phase 7: Simplicity Test

- Ask user to explain the proposed idea in 2 sentences to a first-year undergrad
- If the explanation requires jargon or is longer than 2 sentences → suggest simplification
- Check: is there a simpler version of this idea that captures the core insight?
- Bias toward elegance: "The best ideas can usually be stated without jargon"
- If the idea cannot be simplified further, that's fine — document the 2-sentence version as the `simplicity_statement` in the research brief

## Phase 8: Experiment Design

Based on the proposed direction and adversarial check results:

**Required baselines**: From adversarial check's closest existing work — these are the papers reviewers will expect comparisons against.

**Datasets**: From read analyses — what benchmarks does the field use?
- List standard benchmarks for the domain
- Note any dataset that would be particularly compelling for this direction
- Flag if a needed dataset doesn't exist (opportunity or risk)

**Ablation studies**: From reviewer simulation's anticipated questions — what components need to be isolated and tested?

**Expected results table**: Rough estimates based on SOTA numbers + proposed improvement mechanism

```
| Method | Metric A | Metric B | Metric C |
|--------|----------|----------|----------|
| SOTA baseline 1 | X.X | Y.Y | Z.Z |
| SOTA baseline 2 | X.X | Y.Y | Z.Z |
| Proposed (expected) | ~X.X | ~Y.Y | ~Z.Z |
```

**Compute/data requirements**: Does the user have what's needed?
- GPU hours estimate
- Dataset availability and preprocessing
- Any special hardware or software requirements

## Phase 9: Convergence Decision

**If multiple candidate directions**: Present direction comparison matrix:

| Criterion | Direction A | Direction B | Direction C |
|-----------|------------|------------|------------|
| Novelty | evidence | evidence | evidence |
| Feasibility | evidence | evidence | evidence |
| Impact | evidence | evidence | evidence |
| Risk | evidence | evidence | evidence |
| Reviewer Objection Severity | evidence | evidence | evidence |

Each cell backed by specific evidence from analyzed papers.

**If single direction**: Summarize the direction's strengths and risks.

**User commits** to a direction. Categorize:
- **Incremental**: Solid improvement on existing method, low risk
- **Solid contribution**: Novel approach or significant insight, moderate risk
- **High-impact**: Potentially field-changing, higher risk

**Final output**: Save the complete research brief to workspace.

## Research Brief Output Schema

Save to `.research-workspace/sessions/{slug}/discuss/brief.json`:

```json
{
  "topic": "...",
  "papers_analyzed": ["paper1", "paper2"],
  "assumptions_challenged": [
    { "assumption": "...", "status": "unvalidated", "potential": "high" }
  ],
  "findings": [
    { "claim": "...", "evidence": "paper_id", "confidence": "high|medium" }
  ],
  "open_problems": [
    { "problem": "...", "why_unsolved": "...", "cited_gaps": ["paper_id"] }
  ],
  "proposed_direction": {
    "idea": "...",
    "novelty": "...",
    "feasibility": "...",
    "significance_tiers": { "tier1": "...", "tier2": "...", "tier3": "..." },
    "supporting_evidence": ["paper_id"],
    "simplicity_statement": "2-sentence explanation"
  },
  "adversarial_check": {
    "closest_existing_work": ["paper_id"],
    "differentiation": "..."
  },
  "anticipated_objections": [
    { "objection": "...", "severity": "high|medium|low", "preemptive_response": "..." }
  ],
  "experiment_plan": {
    "baselines": ["..."],
    "datasets": ["..."],
    "ablations": ["..."],
    "expected_results": "..."
  },
  "skills_invoked": ["multimodal:clip", "research-ideation:brainstorming"]
}
```

## Scripts Reused

| Script | Used in |
|--------|---------|
| `s2_search.sh` | Phase 3 (knowledge gap), Phase 4 (adversarial check) |
| `s2_snippet.sh` | Phase 4 (method combo check) |
| `s2_recommend.sh` | Phase 4 (similar work discovery) |
| `s2_citations.sh` | Phase 3 (knowledge gap filling) |
| `s2_references.sh` | Phase 3 (knowledge gap filling) |
| `s2_batch.sh` | Phase 3 (batch metadata for newly discovered papers) |
| `venue_info.sh` | Phase 3 (quality assessment of new papers) |
| `author_info.sh` | Phase 3 (quality assessment of new papers) |
