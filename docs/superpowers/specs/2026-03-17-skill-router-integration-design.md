# Design: Skill Router Integration & Research Workflow Restructuring

**Date**: 2026-03-17
**Status**: Draft
**Author**: Luke (Haopeng Chen) + Claude

## 1. Problem Statement

The current research skill has a complete 6-phase pipeline (discover → triage → read → cite → write → trending) with solid engineering infrastructure (18 bash scripts, multi-source search, zero-hallucination citations). However, analysis and discussion depth is shallow because:

1. All papers are analyzed through the same generic framework regardless of domain
2. No deep discussion/ideation phase exists between reading and writing
3. No domain-specific expert knowledge is injected into analysis
4. No adversarial mechanisms to stress-test research ideas

## 2. Solution Overview

Two major changes:

1. **Skill Router**: A central module that maps paper content to relevant domain skills from orchestra-research/ai-research-skills (21 categories, 85 skills), injecting expert knowledge into each phase
2. **Workflow Restructuring**: Consolidate discover+triage+read into a single scan phase, add a new discuss phase for deep ideation, enhance write with triple review gate

### New Phase Architecture

| Phase | Type | Purpose | Command |
|-------|------|---------|---------|
| **Discover** | Restructured (merge) | Broad field scan: search → triage → quick-read → landscape report | `/research discover "topic"` |
| **Discuss** | New | Deep discussion, iterative ideation, open problem identification, method design | `/research discuss` or `/research discuss <paper>` |
| **Read** | Modified | Standalone deep-read for paper sharing/presentations (lighter domain context) | `/research read <paper>` |
| **Write** | Modified | Paper writing with Triple Review Gate + Consistency Check | `/research write <section>` |
| **Cite** | Minimal change | BibTeX generation (add unified input parsing) | `/research cite <paper>` |
| **Trending** | Modified | Trend tracking with lightweight domain context | `/research trending` |

### Removed Commands

| Old Command | Disposition |
|-------------|-------------|
| `/research survey "topic"` | Replaced by `/research discover "topic"` (now includes triage+quick-read) |
| `/research triage` | Absorbed into discover; no longer a standalone command |

### Migration / Breaking Changes

1. **`/research discover` changes semantics**: Previously search-only, now includes triage + quick-read. Users who relied on discover-only behavior get the expanded output automatically — this is additive, not destructive.
2. **`/research survey` removed**: The old `survey` command ran discover → triage → read as an automatic pipeline. This is replaced by user-driven phase transitions: `discover` (includes triage) → user decides → `discuss` or `read`. Rationale: the old auto-pipeline gave no opportunity for the user to steer between phases; the new flow puts the user in control at each decision point.
3. **Workspace data**: Existing `discover.json` files remain readable. New discover runs produce an extended format (with verdicts + landscape summary). Old `triage.json` files become orphaned but harmless.
4. **`marketplace.json`**: The description references "paper triage" — update to reflect the new architecture after implementation.

## 3. Skill Router Design

### 3.1 Module Location

New file: `skills/research/phases/skill-router.md`

### 3.2 Interface

**Input**:
- `paper_metadata`: title, abstract, keywords, venue (for paper-based phases)
- `topic_description`: free text (for discover phase, where no paper exists yet)
- `phase_type`: discover | discuss | read | write | trending
- `user_domain_override`: optional, from `--domain` flag
- `user_domain_only`: optional, from `--domain-only` flag

**Output**:
```json
{
  "primary": [
    { "category": "multimodal", "skill": "clip", "prompt": "..." },
    { "category": "multimodal", "skill": "llava", "prompt": "..." }
  ],
  "secondary": [
    { "category": "optimization", "skill": "flash-attention", "prompt": "..." }
  ]
}
```

### 3.3 Detection Logic

1. If `user_domain_only` is set → use only specified categories, skip auto-detection
2. If `user_domain_override` is set → auto-detect AND add specified categories (merge)
3. Otherwise → auto-detect from paper_metadata or topic_description

**Auto-detection**: Match keywords from title + abstract against the mapping table (Section 3.4). For each matched category, determine primary vs secondary:

- **Primary**: The keyword relates to the paper's core contribution (what the paper proposes/solves)
- **Secondary**: The keyword relates to a tool/method the paper uses but doesn't contribute to

Heuristic: Keywords appearing in the title or the first 2 sentences of the abstract are likely primary. Keywords appearing only in methodology/experiments context are likely secondary.

### 3.4 Category → Keyword Mapping Table

| # | Category | Trigger Keywords | Available Skills |
|---|----------|-----------------|-----------------|
| 1 | Model-Architecture | transformer, attention mechanism, SSM, state-space, Mamba, RWKV, linear attention, architecture design, backbone | litgpt, mamba, nanogpt, rwkv, torchtitan |
| 2 | Tokenization | tokenizer, BPE, WordPiece, subword, vocabulary design | huggingface-tokenizers, sentencepiece |
| 3 | Fine-Tuning | fine-tuning, LoRA, QLoRA, adapter, PEFT, instruction tuning, SFT | axolotl, llama-factory, peft, unsloth |
| 4 | Mechanistic-Interpretability | interpretability, mechanistic, probing, circuit analysis, sparse autoencoder, superposition, causal intervention | transformer-lens, saelens, pyvene, nnsight |
| 5 | Data-Processing | data curation, deduplication, data quality, pretraining data, data filtering | ray-data, nemo-curator |
| 6 | Post-Training | RLHF, DPO, PPO, GRPO, preference optimization, reward model, alignment training, policy optimization | trl-fine-tuning, grpo-rl-training, openrlhf, simpo, verl |
| 7 | Safety-Alignment | safety, guardrails, jailbreak, red teaming, content moderation, constitutional AI, prompt injection | constitutional-ai, llamaguard, nemo-guardrails, prompt-guard |
| 8 | Distributed-Training | distributed training, model parallelism, tensor parallelism, FSDP, ZeRO, multi-GPU, pipeline parallelism | megatron-core, deepspeed, pytorch-fsdp2, accelerate |
| 9 | Infrastructure | GPU cloud, serverless compute, spot instances, multi-cloud | modal, skypilot, lambda-labs |
| 10 | Optimization | quantization, 4-bit, 8-bit, flash attention, INT4, FP8, model compression, pruning, memory efficiency | flash-attention, bitsandbytes, gptq, awq, hqq, gguf |
| 11 | Evaluation | benchmark, MMLU, HumanEval, GSM8K, leaderboard, evaluation methodology, metrics design | lm-evaluation-harness, bigcode-evaluation-harness, nemo-evaluator |
| 12 | Inference-Serving | inference serving, throughput, PagedAttention, KV cache, batching, deployment optimization | vllm, tensorrt-llm, llama.cpp, sglang |
| 13 | MLOps | experiment tracking, model registry, hyperparameter sweep | weights-and-biases, mlflow, tensorboard |
| 14 | Agents | AI agent, tool use, function calling, ReAct, autonomous agent, multi-agent, agentic workflow | langchain, llamaindex, crewai, autogpt |
| 15 | RAG | retrieval-augmented generation, RAG, vector database, dense retrieval, semantic search | chroma, faiss, sentence-transformers, pinecone, qdrant |
| 16 | Prompt-Engineering | prompt optimization, structured output, constrained generation, prompt programming | dspy, instructor, guidance, outlines |
| 17 | Observability | LLM observability, tracing, LLM monitoring, evaluation pipeline | langsmith, phoenix |
| 18 | Multimodal | multimodal, vision-language, VLM, text-to-image, diffusion, image generation, video understanding, speech recognition, audio generation, CLIP, contrastive learning, segmentation, image editing, style transfer, text-to-video, text-to-motion | clip, whisper, llava, stable-diffusion, segment-anything, blip-2, audiocraft |
| 19 | Emerging-Techniques | mixture of experts, MoE, model merging, long context, context extension, speculative decoding (algorithm-side), knowledge distillation, sparsity | moe-training, model-merging, long-context, speculative-decoding, knowledge-distillation, model-pruning |
| 20 | ML-Paper-Writing | *Not keyword-triggered — auto-invoked by Write phase* | ml-paper-writing |
| 21 | Research-Ideation | *Not keyword-triggered — auto-invoked by Discover (search strategy) and Discuss (ideation)* | brainstorming-research-ideas, creative-thinking-for-research |

**Intra-category skill selection**: When a category is triggered, the router selects the most specific skill based on finer-grained keyword matching.

**General rule**: Default to the first skill listed in the category if no finer-grained keyword matches. If multiple finer-grained keywords match different skills within the same category, select all matching skills (maximum 3 per category).

Examples:
- Fine-Tuning triggered + "LoRA" in text → `peft`
- Fine-Tuning triggered + "full fine-tuning at scale" → `unsloth` or `axolotl`
- Multimodal triggered + text-to-image → `stable-diffusion`
- Multimodal triggered + VLM → `clip` + `llava`
- Optimization triggered + no specific keyword → `flash-attention` (first in list)

### 3.5 Phase-Specific Behavior

| Phase | What gets invoked | Detail level |
|-------|-------------------|-------------|
| **Discover** | Primary only (top 1-2 categories) + `research-ideation` for search strategy | Lightweight — inform search keywords and quick-read assessment |
| **Discuss** | All primary + `research-ideation` (always) | Full depth — expert perspectives injected into every discussion turn |
| **Read** | All primary | Moderate — methodology-level analysis, no cross-paper ideation |
| **Write** | All primary + `ml-paper-writing` (always) | Full depth — technical accuracy check for written content |
| **Trending** | Top 1 primary only | Minimal — one-sentence domain positioning per paper |

### 3.6 User Override

**Syntax**:
```
/research read 2401.12345 --domain fine-tuning,multimodal
/research discover "pose estimation" --domain-only multimodal
```

**Rules**:
1. Multiple categories via comma separation
2. Category names match the mapping table (semantic match OK, e.g., "finetuning" matches "Fine-Tuning")
3. `--domain` = additive (merge with auto-detected categories)
4. `--domain-only` = exclusive (replace auto-detected categories entirely)

### 3.7 Error Handling

| Scenario | Behavior |
|----------|----------|
| No category matched (paper outside AI/ML) | Proceed without domain skill injection; log warning. Phase executes with generic analysis only. |
| Matched skill file not found or fails to load | Skip that skill, proceed with remaining matched skills; log warning. |
| Invalid `--domain` value | Report available category names and ask user to retry. |
| All matched skills fail to load | Proceed without domain injection (same as no-match case). |

### 3.8 Performance Considerations

Each skill invocation adds context to the conversation. To manage this:
- **Discover/Trending**: Skill router runs once per phase invocation, not per paper
- **Read**: Skill router runs once per paper (acceptable — read is a deep operation)
- **Discuss**: Skills are loaded at setup and reused across the discussion loop (not re-invoked each turn)
- **Write**: Skills loaded once per section write
- Within a session, category detection results are cached — if the same topic/papers are processed again, prior routing decisions are reused without re-running detection

## 4. Unified Input Parsing

**Location**: Implemented as a shared section within `skills/research/SKILL.md`. Each phase that needs paper resolution references this shared logic rather than re-implementing it.

Phases that use unified input parsing: **discuss, read, cite**. (Discover takes a topic description, not a paper identifier.)

**Input types**:
- arXiv ID format (e.g., `2401.12345`) → direct lookup via S2/arXiv API
- DOI format (e.g., `10.1109/...`) → direct CrossRef/S2 lookup
- Free text (paper title or keywords) → `s2_match.sh` (exact match first), then `s2_search.sh` + `dblp_search.sh` (if no exact match)

**Clarify flow** (triggered when free-text search returns multiple candidates):

Present candidates with:
- Title + authors + year + venue
- One-sentence core contribution (from abstract)
- Quality marker (CCF/JCR tier, citation count)

User selects one → proceed to the requested phase.

## 5. Phase Designs

### 5.1 Discover Phase (Restructured)

**File**: `skills/research/phases/discover.md` (rewrite)

**Merges**: old discover + triage + quick-read into a single command.

**Flow**:
1. Parse query + invoke skill router with `topic_description`
2. Use `research-ideation` to generate diversified search queries
3. Parallel search (same 3-agent architecture: S2, AlphaXiv, HF)
4. Merge + deduplicate (same logic as current)
5. Quality evaluation (same scoring formula as current)
6. **Quick-read** each paper (top N by score):
   - Fetch overview via AlphaXiv or abstract
   - Generate: one-sentence core contribution + read recommendation (Must read / Worth reading / Skim / Skip)
   - Invoke domain skill for domain-specific relevance assessment
7. Present ranked results with verdicts (replaces old triage output)
8. **Landscape summary**: synthesize a 1-paragraph overview of the field based on all discovered papers — key themes, dominant approaches, recent trends
9. Save to workspace: `discover.json` (includes paper data + verdicts + landscape summary)
10. Expansion options: citation tracing, reference tracing, recommendations, proceed to discuss

**Reused from current codebase**:
- All search scripts (`s2_search.sh`, `s2_bulk_search.sh`, `hf_daily_papers.sh`)
- All quality evaluation scripts (`venue_info.sh`, `author_info.sh`, `ccf_lookup.sh`, `if_lookup.sh`)
- `s2_batch.sh` for batch metadata
- Scoring formula (unchanged)
- Merge/deduplication logic (unchanged)
- AlphaXiv MCP integration (unchanged)
- HF MCP integration (unchanged)

**New additions**:
- Skill router invocation for search strategy
- Quick-read per paper (from triage logic)
- Landscape summary generation

### 5.2 Discuss Phase (New)

**File**: `skills/research/phases/discuss.md` (new)

**Entry**: `/research discuss` (uses current session's discover output) or `/research discuss <paper>` (starts from a specific paper, uses unified input parsing)

**Flow**:

```
Phase 1: Setup
├── Load discover report + any existing read analyses from workspace
├── Invoke skill router (all primary + research-ideation)
└── Load user's researcher context if available

Phase 2: Assumption Surfacing
├── List shared assumptions across surveyed papers
├── Challenge: which assumptions are validated vs inherited convention?
└── Flag assumptions worth questioning as candidate research angles

Phase 3: Discussion Loop (iterative, user-driven)
│   [Phases 4-9 trigger when user signals readiness, e.g., "let's finalize"
│    or "I think we have a direction". User can request any phase individually
│    (e.g., "run adversarial check"), skip inapplicable phases (e.g., skip
│    Experiment Design for theoretical work), or loop back from any phase
│    to Phase 3 for further discussion.]
├── Propose analysis perspectives (infused with domain skill expertise)
├── User discusses / challenges / proposes directions
├── Knowledge gap detection:
│   ├── Method/baseline mentioned but not in session → auto discover+read
│   ├── User questions conclusion without comparison data → targeted read
│   └── Domain skill suggests related work → supplementary discover
├── Out-of-domain search:
│   ├── Abstract the core problem to a general form
│   ├── Search for analogous solutions in other fields
│   └── Present cross-domain insights
└── Continuously update research brief (findings, open problems, directions)

Phase 4: Adversarial Novelty Check
├── For each proposed direction:
│   ├── s2_search.sh with the direction as query
│   ├── s2_snippet.sh for the specific method combination
│   └── s2_recommend.sh with the direction's key papers as positives
├── Retrieve top 5 closest existing papers
├── Side-by-side comparison: how does the proposed idea differ?
└── Flag if differentiation is insufficient ("likely incremental")

Phase 5: Reviewer Simulation
├── Generate 3-4 likely reviewer objections
├── Identify weakest claims in the motivation
├── List demanded baselines and ablations
└── Store as anticipated_objections in research brief

Phase 6: Significance Test (3 tiers)
├── Tier 1: Does this affect real systems/users? (concrete failure mode required)
├── Tier 2: If solved, does the community approach the broader problem differently?
├── Tier 3: Is the expected improvement meaningful or marginal?
└── Explicit flag if any tier is weak

Phase 7: Simplicity Test
├── Can the idea be explained in 2 sentences to an undergrad?
├── If not → suggest simplification
└── Bias toward elegance over complexity

Phase 8: Experiment Design
├── Required baselines (from closest existing work)
├── Datasets to evaluate on
├── Ablation studies needed
├── Expected results table (rough estimates)
└── Compute/data requirements vs user's resources

Phase 9: Convergence Decision
├── Direction comparison matrix (if multiple candidates)
│   ├── Novelty | Feasibility | Impact | Risk | Reviewer Objection Severity
│   └── Each cell backed by evidence from analyzed papers
├── User commits to a direction
└── Final research brief saved to workspace
```

**Output**: Research brief persisted to `.research-workspace/sessions/{slug}/discuss/brief.json`:

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

**Scripts reused**:
- `s2_search.sh`, `s2_snippet.sh`, `s2_recommend.sh` for adversarial novelty check
- `s2_citations.sh`, `s2_references.sh` for knowledge gap filling
- `s2_batch.sh` for batch metadata on newly discovered papers
- `venue_info.sh`, `author_info.sh` for quality assessment of new papers
- All content fetching (AlphaXiv MCP, arXiv PDF) for gap-filling reads

### 5.3 Read Phase (Modified)

**File**: `skills/research/phases/read.md` (modify)

**Changes from current**:
1. Add unified input parsing (arXiv ID, DOI, or title with clarify flow)
2. Add skill router invocation after paper identity is resolved (before analysis)
3. Domain skills provide expert perspective in the structured analysis
4. Keep as standalone — no cross-paper comparison, no research-ideation
5. Suitable for paper sharing/presentation use case

**Unchanged**:
- Content fetching fallback chain (AlphaXiv MCP → curl → arXiv PDF → publisher)
- Appendix/supplementary handling
- Code inspection via AlphaXiv MCP
- Cross-paper evidence via `s2_snippet.sh`
- Structured analysis format
- Workspace persistence

**New in structured analysis output**:
```markdown
### Domain Expert Perspective
[Injected by skill router — e.g., "From a PEFT perspective, the LoRA rank choice of 16
is conservative; recent work shows rank 4 achieves comparable results with 4x less
parameters..."]
```

**New in workspace output** (`read/{paper_id}.json`): Add `"skills_invoked": [...]` field for debugging and reproducibility.

### 5.4 Write Phase (Modified)

**File**: `skills/research/phases/write.md` (modify)

**Changes from current**:
1. Add skill router invocation for domain-specific technical accuracy
2. Add discuss phase output (research brief) as primary context source
3. Add Triple Review Gate for abstract + introduction
4. Add Consistency Check for method + experiments + conclusion
5. Keep existing: output format detection, cite verification, humanizer, ml-paper-writing

**Triple Review Gate** (abstract + introduction only):

After writing initial draft of abstract or introduction, auto-trigger three review perspectives:

| Perspective | Focus | Key Questions |
|-------------|-------|---------------|
| **Reviewer** | Technical rigor | Is motivation backed by concrete failure mode? Are contributions clearly distinguished from prior work? Do claims align with experiments? |
| **AC/SAC** | Novelty & significance | Can the contribution be summarized in one sentence? Is it incremental or substantial? Is there concurrent work risk? |
| **Senior Researcher** | Impact & elegance | "If this succeeds, who changes their behavior?" Is the framing revealing a deeper insight? Is this the simplest formulation? |

Each perspective outputs 2-3 specific revision suggestions pointing to concrete sentences. User decides which to adopt. Optional re-run after revision.

**Consistency Check** (method, experiments, conclusion):

Lightweight structural cross-reference scan:
- Introduction lists N contributions → experiments has corresponding table/figure for each?
- Method assumes specific input format → dataset actually provides that format?
- Abstract claims "state-of-the-art" → results table shows superiority over all listed baselines?
- Conclusion doesn't overclaim beyond what experiments demonstrate?

Flag inconsistencies for user to resolve.

**Context source priority** (updated):
1. Research brief from discuss phase (`discuss/brief.json`) — primary framing source
2. Read analyses from workspace — detailed technical content
3. Existing `.tex` files — current draft state
4. Cite-log — verified citations
5. User's direct instructions

### 5.5 Cite Phase (Minimal Change)

**File**: `skills/research/phases/cite.md` (minor modify)

**Only change**: Add unified input parsing (arXiv ID, DOI, or title with clarify flow).

Everything else unchanged — BibTeX source chain, DBLP matching, quality evaluation, iron rules, workspace persistence.

### 5.6 Trending Phase (Modified)

**File**: `skills/research/phases/trending.md` (modify)

**Changes**:
1. Add skill router invocation (lightweight: top 1 primary category per paper)
2. Domain skill provides one-sentence expert assessment beyond generic relevance tier
3. For high-tier papers: domain skill assesses significance ("why this matters for the field")

**Unchanged**:
- HF daily papers + AlphaXiv hot sources
- Personalization filter (High/Medium/Low tiers)
- Deduplication
- Presentation format
- Follow-up options

## 6. File Change Plan

### New Files

| File | Purpose |
|------|---------|
| `skills/research/phases/skill-router.md` | Central skill routing module |
| `skills/research/phases/discuss.md` | Deep discussion + ideation phase |

### Modified Files

| File | Changes |
|------|---------|
| `skills/research/SKILL.md` | Update routing table (remove `survey` and `triage`, add `discuss`); add skill-router preload description; update dependencies |
| `skills/research/phases/discover.md` | Major rewrite: absorb triage + quick-read; add skill router + landscape summary; update expansion options (remove triage, add discuss) |
| `skills/research/phases/read.md` | Add unified input parsing; add skill router invocation; add domain expert perspective to output |
| `skills/research/phases/write.md` | Add Triple Review Gate; add Consistency Check; add skill router; add research brief as context source |
| `skills/research/phases/cite.md` | Add unified input parsing (arXiv ID / DOI / title with clarify) |
| `skills/research/phases/trending.md` | Add skill router (lightweight); enhance high-tier assessment |

### Discarded Files

| File | Reason |
|------|--------|
| `skills/research/phases/triage.md` | Fully absorbed into the new discover phase. All triage logic (fetch overview, generate verdict, recommend read/skip) is now part of discover's quick-read step. |

### Unchanged Files

| File | Reason |
|------|--------|
| `skills/research/scripts/init.sh` | Env loading, no changes needed |
| `skills/research/scripts/s2_search.sh` | Reused as-is by discover, discuss |
| `skills/research/scripts/s2_bulk_search.sh` | Reused as-is by discover |
| `skills/research/scripts/s2_batch.sh` | Reused as-is by discover, discuss |
| `skills/research/scripts/s2_citations.sh` | Reused as-is by discover, discuss |
| `skills/research/scripts/s2_references.sh` | Reused as-is by discover, discuss |
| `skills/research/scripts/s2_recommend.sh` | Reused as-is by discuss (adversarial check) |
| `skills/research/scripts/s2_snippet.sh` | Reused as-is by discuss, read |
| `skills/research/scripts/s2_match.sh` | Reused as-is by unified input parsing |
| `skills/research/scripts/dblp_search.sh` | Reused as-is by cite, unified input parsing (discuss, read, cite) |
| `skills/research/scripts/dblp_bibtex.sh` | Reused as-is by cite |
| `skills/research/scripts/crossref_search.sh` | Reused as-is by cite |
| `skills/research/scripts/doi2bibtex.sh` | Reused as-is by cite |
| `skills/research/scripts/hf_daily_papers.sh` | Reused as-is by trending |
| `skills/research/scripts/venue_info.sh` | Reused as-is by discover, discuss |
| `skills/research/scripts/ccf_lookup.sh` | Reused as-is (called by venue_info) |
| `skills/research/scripts/if_lookup.sh` | Reused as-is (called by venue_info) |
| `skills/research/scripts/author_info.sh` | Reused as-is by discover, discuss |
| `skills/research/data/ccf_2026.sqlite` | Reference data, no changes |
| `skills/research/data/ccf_2026.jsonl` | Reference data, no changes |
| `skills/research/data/impact_factor.sqlite3` | Reference data, no changes |
| `skills/research/tests/*` | Existing tests remain valid. New integration tests for skill-router and discuss phase are out of scope for this spec and will be covered in a separate testing plan. |
| `skills/research/.env.example` | No new env vars needed |
| `skills/research/.env` | User's API keys, no changes needed (in .gitignore) |

## 7. Workspace Changes

### New workspace paths

```
.research-workspace/sessions/{slug}/
  discover.json          # Updated: now includes verdicts + landscape summary
  discuss/
    brief.json           # NEW: research brief output
  read/{paper_id}.json   # Unchanged
  cite/{paper_id}.bib    # Unchanged
  cite/cite-log.json     # Unchanged
```

### Removed workspace paths

```
  triage.json            # No longer generated (absorbed into discover.json)
```

## 8. Updated Dependencies

### Required skills/plugins (updated)

| Dependency | Used by | Status |
|------------|---------|--------|
| `pua:high-agency` | Preload | Existing |
| `pua:pua-en` | Pressure escalation | Existing |
| `ml-paper-writing` (Orchestra-Research) | Write phase | Existing |
| `humanizer` | Write phase style review | Existing |
| `brainstorming-research-ideas` (Orchestra-Research) | Discuss phase, Discover phase | **New** |
| `creative-thinking-for-research` (Orchestra-Research) | Discuss phase | **New** |
| All 21 categories from Orchestra-Research | Via skill router | **New** (resolved via Claude Code's `Skill` tool invocation mechanism; do NOT hardcode filesystem paths to plugin cache) |

### Required MCP servers (unchanged)
- AlphaXiv MCP (with degraded mode fallback)
- HF MCP (Hugging Face)

### Required API keys (unchanged)
- Semantic Scholar `S2_API_KEY`

## 9. Updated Routing Table (SKILL.md)

| Input pattern | Phase | Module |
|---------------|-------|--------|
| `/research discover "topic"` | discover (consolidated) | `phases/discover.md` |
| `/research discuss` | discuss (current session) | `phases/discuss.md` |
| `/research discuss <paper>` | discuss (from specific paper) | `phases/discuss.md` |
| `/research read <paper>` | read (standalone) | `phases/read.md` |
| `/research cite <paper>` | cite | `phases/cite.md` |
| `/research write <section>` | write | `phases/write.md` |
| `/research trending` | trending | `phases/trending.md` |

`<paper>` accepts: arXiv ID, DOI, or paper title (with clarify flow if ambiguous).

All commands support optional `--domain <categories>` or `--domain-only <categories>` flags.

## 10. Iron Rules (Updated)

Rules 1-6 are defined in the current SKILL.md and remain unchanged (zero hallucination citations, BibTeX priority, high-agency preload, quality gate, source tracing, own model for analysis). New additions:

7. **Domain skill grounding** — domain skills provide expert context, but all factual claims must still trace to paper content or API responses, never to skill-generated assertions alone
8. **Adversarial before commitment** — no research direction is finalized without adversarial novelty check against existing literature
9. **Triple review for framing** — abstract and introduction must pass reviewer, AC/SAC, and senior researcher perspectives before finalization
10. **Simplicity preference** — between two approaches of similar merit, prefer the simpler one
