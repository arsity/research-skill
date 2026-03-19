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

**Codex co-brainstorm** (co-thinker mode):
Invoke `mcp__codex__codex` per Cross-Model Collaboration #1 in SKILL.md. Send the papers analyzed and field context. Ask Codex to independently surface assumptions the field takes for granted.

Merge Claude's and Codex's assumption lists:
- Deduplicate overlapping assumptions (overlap = both models flagged the same underlying assumption, even if worded differently)
- Label each assumption's source: `[Claude]`, `[Codex]`, or `[Both]`
- Assumptions flagged by both models are higher-confidence candidates; assumptions flagged by only one model may represent genuine blind spots worth extra attention

Flag unvalidated assumptions as candidate research angles — "What if this assumption is wrong?"

Present merged list to user for discussion before proceeding.

**Checkpoint**: After Phase 2 completes, write checkpoint to `checkpoints/discuss_phase2_{timestamp}.json` capturing: papers analyzed, assumptions surfaced (with status, potential ratings, and source labels), and domain skills loaded.

## Phase 3: Discussion Loop

Iterative, three-way discussion (user + Claude + Codex). This is the core of the discuss phase.

**Analysis perspectives**: Propose analysis perspectives infused with domain skill expertise. Respond to user's questions, challenges, and proposed directions.

**Codex as third participant** (co-thinker mode):
Per Cross-Model Collaboration #2 in SKILL.md, Codex joins the discussion as an ongoing third voice. The interaction model per turn:
1. User raises a question or proposes a direction
2. Claude responds with analysis
3. Codex is consulted on the same question — phrased to elicit a **complementary angle** (e.g., if Claude analyzed methodology, ask Codex about practical feasibility or applications, and vice versa)
4. Present both responses labeled `[Claude]` and `[Codex]`; user synthesizes and steers

**When to invoke Codex within a turn**:
- The discussion hits a fork (multiple possible directions)
- A novel claim is made that benefits from independent verification
- The user questions a conclusion or asks "what do you think about X?"
- Claude expresses uncertainty

**When to skip Codex within a turn**:
- The turn is clarificational (user providing background info)
- The question is about a specific paper's content (read phase + domain skills handle this)
- The user explicitly directs the question to Claude only

**Knowledge gap detection**:
- Method/baseline mentioned but not in current session → auto-trigger:
  - `bash scripts/s2_search.sh "<method>" 5` to find the paper
  - Quick-read the found paper to fill the gap
- User questions a conclusion without comparison data → targeted read of the comparison paper
- Domain skill suggests related work → supplementary discover with `s2_search.sh`
- **If a knowledge-gap search returns 0 results**: apply Iron Rule 12 (root cause before retry) — diagnose whether the query is too specific, the method name has alternate spellings, or the paper is too new for S2 indexing. If the search still fails after diagnosis, trigger PUA escalation per the PUA Pressure Escalation table in SKILL.md.

**Knowledge gap quick-reads** (cache-aware): Check `cache/{paper_id}/overview.md` first. On cache miss, fetch `curl -sL "https://alphaxiv.org/overview/{arxiv_id}.md"` and save to cache. If alphaxiv returns 404, fall back to S2 abstract or arXiv PDF (also cache the result). See Paper Cache in SKILL.md.

**Out-of-domain search**:
- Abstract the core problem to a general form (e.g., "signal recovery under noise" instead of "pose estimation in fog")
- `bash scripts/s2_search.sh "<abstracted query>" 10` in adjacent fields
- Present cross-domain insights and analogies

**Continuous updates**: Throughout the discussion, continuously update the research brief with findings, open problems, candidate directions, and evidence.

**Transition note**: Phases 4-9 trigger when user signals readiness (e.g., "let's finalize" or "I think we have a direction"). User can request any phase individually (e.g., "run adversarial check"), skip inapplicable phases (e.g., skip Experiment Design for theoretical work), or loop back from any phase to Phase 3 for further discussion. **Exception: Phase 4 (Adversarial Novelty Check) and Phase 9 (Convergence Decision) are non-skippable per Iron Rules 8 and the Cross-Model Collaboration protocol.** No direction is finalized without adversarial vetting.

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

3. **Cross-model adversarial review** (novelty gate):
   Invoke `mcp__codex__codex` per Cross-Model Collaboration #3 in SKILL.md. Send:
   - The proposed direction (idea + method sketch)
   - The top 5 closest existing papers (title + core contribution + differentiation analysis)
   - The research brief so far

   Ask: "As a skeptical reviewer at {target venue}: (1) Is the claimed novelty real or superficial? (2) What existing work was missed? (3) What's the strongest argument against this direction?"

   Parse response for actionable concerns. Present to user labeled `[Cross-model review]` alongside Claude's own analysis.

   If Codex MCP is unavailable, skip and proceed with Claude-only analysis.

4. **Verdict**:
   - If differentiation is insufficient (from either Claude or cross-model review) → flag as "likely incremental" and suggest pivots
   - If concurrent work detected (arXiv preprint from last 6 months with >70% conceptual overlap) → warn explicitly
   - If clearly novel → proceed with confidence

**Checkpoint**: After Phase 4 completes, write checkpoint to `checkpoints/discuss_phase4_{timestamp}.json` capturing: assumptions challenged, findings so far, proposed directions, adversarial check results, cross-model concerns (if any), and user decisions made so far.

## Phase 5: Reviewer Simulation

Two models independently generate reviewer objections, then merge for maximum coverage. If real OpenReview data is available in cache for any closely related paper, incorporate it first.

**Real reviewer data** (highest authority):
Check `cache/*/openreview/reviews.json` for papers in the current session that are closely related to the proposed direction. If real reviews exist:
- Extract objections and concerns raised by actual reviewers
- Note the venue and acceptance outcome
- These take priority over simulated objections — label as `[OpenReview: {venue} {year}]`
- Use them as anchors: "Real reviewers at ICLR 2024 raised X about a similar approach — we must address this."

**Claude's objections**: Generate 3-4 likely reviewer objections for the proposed direction. For each:
- What is the weakest claim in the current framing?
- What baseline would a reviewer demand? ("Why not compare against [method X]?")
- What ablation is essential to prove the contribution?
- Severity rating: High / Medium / Low

**Codex's objections** (adversarial mode):
Invoke `mcp__codex__codex` per Cross-Model Collaboration #4 in SKILL.md. Send the proposed direction + research brief. Ask Codex to independently generate 3-4 reviewer objections with the same structure.

**Merge and deduplicate**:
- Combine both sets of objections
- Deduplicate where both models raise the same underlying concern
- Label each: `[Claude]`, `[Codex]`, or `[Both]`
- Objections raised by both models are highest priority — if two independent models see the same weakness, reviewers almost certainly will too

Frame as specific review comments:
- "Reviewer 2 would ask: 'Why not compare against [method X]? The improvement over [method Y] alone is not convincing.'" `[Both]`
- "Reviewer 3 would note: 'The claim about [Z] is not supported by the experiments in Table 2.'" `[Codex]`

Store as `anticipated_objections` in the research brief with severity ratings, source labels, and preemptive responses.

## Phase 6: Significance Test

Three-tier assessment, evaluated independently by both Claude and Codex.

**Claude's assessment**:

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

**Codex's assessment** (adversarial mode):
Invoke `mcp__codex__codex` per Cross-Model Collaboration #5 in SKILL.md. Send the proposed direction + Claude's significance analysis. Ask Codex to independently evaluate all three tiers and flag any that are weak.

**Reconcile**: Present both assessments side by side. Where the two models disagree on a tier's strength (one says strong, the other says weak), highlight the disagreement — this indicates genuine uncertainty that the user must resolve.

Explicit flag if **either model** rates any tier as weak — user must acknowledge before proceeding.

## Phase 7: Simplicity Test

- Ask user to explain the proposed idea in 2 sentences to a first-year undergrad
- If the explanation requires jargon or is longer than 2 sentences → suggest simplification
- Check: is there a simpler version of this idea that captures the core insight?
- Bias toward elegance: "The best ideas can usually be stated without jargon"

**Codex as cold reader** (per Cross-Model Collaboration #6 in SKILL.md):
Invoke `mcp__codex__codex`. Send the user's 2-sentence explanation **without any prior discussion context** — no research brief, no paper list, no domain background. Just the 2 sentences.

Ask Codex: "Based only on these 2 sentences, explain back what the research idea is and what makes it novel. What is unclear or ambiguous?"

The logic: Claude has been in the discussion for hours and has deep context — it would find any explanation easy to understand. Codex, coming in cold, is a much more honest test of whether the explanation stands on its own. If Codex can accurately reconstruct the idea from 2 sentences alone, the simplicity statement is strong. If Codex misunderstands or asks clarifying questions, the explanation needs work.

- If Codex reconstructs accurately → document as `simplicity_statement` in the research brief
- If Codex misunderstands → iterate with user to refine, re-test with Codex until it passes

## Phase 8: Experiment Design

Based on the proposed direction and adversarial check results, **Claude and user draft the experiment plan together first**, then Codex reviews.

**Claude drafts**:

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

**Codex blind-spot review** (per Cross-Model Collaboration #7 in SKILL.md):
After Claude and user agree on the experiment plan draft, invoke `mcp__codex__codex`. Send the complete experiment plan + research brief. Ask:
- "What baselines are missing that a reviewer would demand?"
- "What ablation is essential but not listed?"
- "Are there datasets better suited to this direction that were overlooked?"
- "Is the expected results table realistic given the proposed method?"

Present Codex's feedback to user. Incorporate any valid additions into the plan before proceeding to Phase 9.

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

**Codex final sanity check** (adversarial mode — this is the last safety net before months of experiments):
Invoke `mcp__codex__codex` per Cross-Model Collaboration #8 in SKILL.md. Send the **complete research brief** (all findings, proposed direction, adversarial check, reviewer objections, significance assessment, experiment plan). Ask:
- "Given everything in this brief, would you recommend this direction for {target venue}?"
- "What is the single biggest risk?"
- "What would make you abandon this direction?"

Present Codex's response labeled `[Final cross-model check]`. If Codex identifies a critical concern not previously addressed, the user must explicitly acknowledge it before committing.

**User commits** to a direction. Categorize:
- **Incremental**: Solid improvement on existing method, low risk
- **Solid contribution**: Novel approach or significant insight, moderate risk
- **High-impact**: Potentially field-changing, higher risk

**Final output**: Save the complete research brief to workspace.

**Checkpoint**: Write final checkpoint to `checkpoints/discuss_final_{timestamp}.json` with status `completed`, referencing `discuss/brief.json` as the primary artifact.

## Research Brief Output Schema

Save to `.research-workspace/sessions/{slug}/discuss/brief.json`:

```json
{
  "topic": "...",
  "papers_analyzed": ["paper1", "paper2"],
  "assumptions_surfaced": [
    { "assumption": "...", "status": "unvalidated|validated|violated", "potential": "high|medium|low", "source": "claude|codex|both" }
  ],
  "findings": [
    { "claim": "...", "evidence": "paper_id", "confidence": "high|medium" }
  ],
  "open_problems": [
    { "problem": "...", "why_unsolved": "...", "cited_gaps": ["paper_id"] }
  ],
  "candidate_directions": [
    {
      "idea": "...",
      "novelty": "...",
      "feasibility": "...",
      "significance_narrative": { "tier1": "freeform description", "tier2": "freeform description", "tier3": "freeform description" },
      "supporting_evidence": ["paper_id"],
      "simplicity_statement": "2-sentence explanation"
    }
  ],
  "committed_direction_index": 0,
  "adversarial_check": {
    "closest_existing_work": ["paper_id"],
    "differentiation": "...",
    "cross_model_concerns": [
      { "concern": "...", "source": "codex", "user_response": "accepted|dismissed|deferred" }
    ]
  },
  "anticipated_objections": [
    {
      "objection": "...",
      "weakest_claim": "...",
      "missing_baseline": "...",
      "essential_ablation": "...",
      "severity": "high|medium|low",
      "source": "claude|codex|both",
      "preemptive_response": "..."
    }
  ],
  "significance_assessment": {
    "_note": "Structured pass/fail from Phase 6. Authoritative over candidate_directions[].significance_narrative, which is freeform context written during earlier ideation.",
    "claude": { "tier1": "strong|weak", "tier2": "strong|weak", "tier3": "strong|weak" },
    "codex": { "tier1": "strong|weak", "tier2": "strong|weak", "tier3": "strong|weak" },
    "disagreements": ["tier where models disagree, if any"]
  },
  "final_cross_model_check": {
    "recommendation": "proceed|proceed_with_caution|reconsider",
    "biggest_risk": "...",
    "abandon_criteria": "...",
    "user_acknowledged": true
  },
  "commitment_category": "incremental|solid_contribution|high_impact",
  "experiment_plan": {
    "baselines": ["..."],
    "datasets": ["..."],
    "ablations": ["..."],
    "expected_results": "...",
    "compute_requirements": { "gpu_hours": "...", "dataset_availability": "...", "special_requirements": "..." },
    "codex_blind_spot_review": ["concern1", "concern2"]
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
