---
name: research
description: Unified academic research lifecycle skill. Use for literature discovery, deep discussion, paper reading, citation management, paper writing, and trend monitoring. Triggers on /research command.
---

# Research Skill

Full academic research lifecycle: discover, discuss, read, cite, write, trending.

## Preload

On every invocation, before doing anything else:

1. **Load high-agency skill**: Invoke `pua:high-agency` to ensure exhaustive search and retry behavior
2. **Load skill router**: Read `phases/skill-router.md` for domain skill mapping. Parse any `--domain` or `--domain-only` flags from user input.

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

## Workspace

On first invocation, create `.research-workspace/` in the current working directory if it doesn't exist:

```bash
mkdir -p .research-workspace/sessions
echo '{"sessions": [], "current_session": null}' > .research-workspace/state.json
```

Each discover invocation creates a session: `.research-workspace/sessions/{topic-slug}-{date}/`
Contents:
- `discover.json` — search results with verdicts + landscape summary
- `discuss/brief.json` — research brief from discuss phase
- `read/{paper_id}.json` — structured paper analyses
- `cite/{paper_id}.bib` — verified BibTeX entries
- `cite/cite-log.json` — citation metadata and sources
- `write/{section}.md` — generated section text with metadata (output format, citations used, review gates applied)
- `cache/{paper_id}/` — raw paper content cache (see Paper Cache)
- `checkpoints/` — phase completion checkpoints (see State Persistence)

## Paper Cache

Fetched paper content is expensive (network latency, rate limits, AlphaXiv/arXiv availability). After context compaction, all prior reads are lost. The cache stores raw content locally so it never needs to be re-fetched.

### Cache directory structure

```
.research-workspace/sessions/{slug}/cache/{paper_id}/
├── overview.md          # AlphaXiv structured overview (if available)
├── fulltext.md          # AlphaXiv full text (if available)
├── paper.pdf            # arXiv or publisher PDF (if downloadable)
├── supplementary.pdf    # Supplementary/appendix PDF (if found)
├── openreview/
│   ├── reviews.json     # OpenReview official reviews (if venue uses OpenReview)
│   ├── rebuttal.json    # Author rebuttals (if available)
│   └── meta_review.json # AC/SAC meta-review (if available)
└── cache_meta.json      # What was cached, when, from where
```

### cache_meta.json schema

```json
{
  "paper_id": "s2_id or arxiv_id",
  "arxiv_id": "2401.12345",
  "doi": "10.xxxx/...",
  "cached_at": "ISO 8601",
  "contents": {
    "overview": { "source": "alphaxiv", "status": "cached|404|not_attempted" },
    "fulltext": { "source": "alphaxiv", "status": "cached|404|not_attempted" },
    "pdf": { "source": "arxiv|publisher|s2_open_access", "status": "cached|404|not_attempted" },
    "supplementary": { "source": "publisher|arxiv", "status": "cached|404|not_attempted" },
    "openreview": { "source": "openreview_api", "status": "cached|not_found|private|no_credentials|not_attempted", "venue": "ICLR 2024" }
  }
}
```

### Cache protocol

**On any paper content fetch** (read, discover quick-read, discuss knowledge gap):

1. **Check cache first**: Look for `.research-workspace/sessions/{slug}/cache/{paper_id}/`. If `cache_meta.json` exists, read it to determine what's available.
2. **Use cached content**: If the needed content type has `status: "cached"`, read from the local file. Do not re-fetch.
3. **Fetch and cache on miss**: If `status` is `"not_attempted"` or the cache directory doesn't exist, fetch from the network and save to cache.
4. **Respect 404s**: If a previous fetch returned 404 (`status: "404"`), do not retry — the content genuinely doesn't exist. Exception: retry after 7 days (AlphaXiv may add new papers).
5. **Cross-session sharing**: The cache is per-session. If the same paper appears in a different session, it will be re-fetched (sessions represent different research topics and may need different timeframes of content).

### OpenReview integration

For papers published at venues that use OpenReview (ICLR, NeurIPS, ICML, and others), attempt to fetch review records.

**Authentication required**: The OpenReview API requires a Bearer token. Obtain via `POST https://api2.openreview.net/login` with username/password, or use the `openreview-py` Python client. If no OpenReview credentials are configured, skip OpenReview fetch entirely (log warning, set `status: "no_credentials"`).

**Credentials config**: Set `OPENREVIEW_USER` and `OPENREVIEW_PASS` in `.claude/settings.local.json` under `"env"`. These are optional — the entire OpenReview integration is a best-effort enhancement.

**Fetch flow** (when credentials are available):

1. **Detect OpenReview venue**: Check if the paper's venue (from S2 metadata) is known to use OpenReview. Known venues: ICLR, NeurIPS, ICML, COLM, EMNLP, ACL (recent years), AISTATS.
2. **Authenticate**: `curl -sL -X POST "https://api2.openreview.net/login" -d '{"id":"$OPENREVIEW_USER","password":"$OPENREVIEW_PASS"}'` → extract `token` from response.
3. **Search OpenReview**: `curl -sL -H "Authorization: Bearer $TOKEN" "https://api2.openreview.net/notes/search?query={title}&source=forum&limit=3"` — match by title + year.
4. **Fetch reviews**: If forum found, fetch all replies: `curl -sL -H "Authorization: Bearer $TOKEN" "https://api2.openreview.net/notes?forum={forum_id}"`. Parse into:
   - **Official reviews**: invitations containing "Official_Review"
   - **Author rebuttals**: invitations containing "Rebuttal" or author replies
   - **Meta-reviews**: invitations containing "Meta_Review" or "Decision"
5. **Save**: Write `reviews.json`, `rebuttal.json`, `meta_review.json` to `cache/{paper_id}/openreview/`.
6. **Graceful degradation**: If OpenReview API returns 403 (private reviews), empty results, or network error, set `status: "not_found"` or `"private"` and proceed. Do NOT freeze 403 as permanent — reviews may become public after camera-ready. OpenReview data is valuable but never required.

### How cache integrates with phases

| Phase | Cache interaction |
| --- | --- |
| **read** Step 2 | Check cache before AlphaXiv/arXiv/publisher fetch. Save all fetched content to cache. Also attempt OpenReview fetch for the paper. |
| **discover** Step 6 (quick-read) | Check cache for overview.md. Save if fetched. Skip full OpenReview fetch (too heavy for batch quick-read). |
| **discuss** Phase 3 (knowledge gap) | Check cache before quick-read fetch. Save if fetched. |
| **discuss** Phase 5 (reviewer simulation) | If `openreview/reviews.json` exists in cache for any analyzed paper, incorporate real reviewer concerns into the simulation — real objections take priority over simulated ones. |
| **write** (related-work, intro) | Read cached content for positioning accuracy instead of relying on summaries alone. |

## State Persistence

Long research sessions (especially discover → discuss → write chains) risk losing progress to context compaction. Each phase writes a checkpoint on completion so work can be resumed.

### Checkpoint format

Save to `.research-workspace/sessions/{slug}/checkpoints/{phase}_{timestamp}.json`:

```json
{
  "phase": "discover|discuss|read|cite|write|trending",
  "status": "completed|in_progress|failed",
  "timestamp": "ISO 8601",
  "completed_steps": ["step1", "step2"],
  "pending_steps": ["step3"],
  "key_artifacts": {
    "discover_json": "relative path if exists",
    "brief_json": "relative path if exists",
    "read_analyses": ["paper_id1", "paper_id2"],
    "cite_log": "relative path if exists"
  },
  "context_summary": "1-2 sentence summary of what was accomplished and what remains",
  "skills_loaded": ["multimodal:clip", "pua:high-agency"],
  "user_decisions": ["chose direction A over B", "skipped experiment design"]
}
```

### Write checkpoint

Each phase writes its checkpoint **after** saving its primary artifact (discover.json, brief.json, etc.). The checkpoint is a lightweight pointer — the real data lives in the phase artifacts.

### Recovery on context compaction

If a session resumes after context compaction (detected by: user continues a `/research` command but prior conversation context is unavailable):

1. Read `.research-workspace/state.json` → identify current session
2. Read the latest checkpoint in `checkpoints/` → reconstruct phase state
3. Read referenced artifacts (discover.json, brief.json, etc.) as needed
4. Reload domain skills from the checkpoint's `skills_loaded` list
5. Resume from `pending_steps` — do not re-run completed steps
6. Inform the user: "Resuming from checkpoint: {context_summary}"

### Discuss phase mid-conversation checkpoints

The discuss phase is uniquely long-running (multi-turn). It writes **incremental checkpoints** at two points:
- After Phase 2 (Assumption Surfacing) completes
- After Phase 4 (Adversarial Novelty Check) completes

These capture the evolving research brief so that even if compaction occurs mid-discussion, the accumulated findings, open problems, and proposed directions are preserved.

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

All commands support:
- `--domain <cat1,cat2>`: Additive — merge with auto-detected categories
- `--domain-only <cat1,cat2>`: Exclusive — use only these categories

Category names match the skill-router mapping table (semantic match OK).

## Timeout Policy

Each parallel search agent has a 60-second timeout. If an agent times out or errors, proceed with results from the remaining agents. Log the failure but do not block.

## Iron Rules

1. **Zero hallucination citations** — every citation from an API call, never from model memory
2. **BibTeX priority** — DBLP > CrossRef > S2 (AlphaXiv is content-only, not a citation source)
3. **High-agency preload** — loaded at skill start, drives exhaustive search and retry
4. **Quality gate** — no paper presented to user without quality evaluation
5. **Source tracing** — every citation tagged with data source ("via DBLP", "via CrossRef", etc.)
6. **Own model for analysis** — never rely on AlphaXiv's AI-generated answers; use their content extraction, analyze with own Claude
7. **Domain skill grounding** — domain skills provide expert context, but all factual claims must still trace to paper content or API responses, never to skill-generated assertions alone
8. **Adversarial before commitment** — no research direction is finalized without adversarial novelty check against existing literature
9. **Multi-perspective review for framing** — abstract and introduction must pass reviewer, AC/SAC, and senior researcher perspectives + cross-model gate before finalization; related-work must pass coverage & fairness check (Claude + Codex)
10. **Simplicity preference** — between two approaches of similar merit, prefer the simpler one
11. **Verify before completion** — invoke `superpowers:verification-before-completion` before presenting final output in cite, write, and discover phases (see each phase for details)
12. **Root cause before retry** — when any script or API call fails, diagnose the root cause (API key expired? rate limit? malformed query? network error?) before retrying or switching strategy. Never retry blindly. (Borrowed from `superpowers:systematic-debugging`)

## PUA Pressure Escalation

`pua:high-agency` is pre-loaded at skill start (see Preload). In addition, invoke `pua:pua` (Chinese) or `pua:pua-en` (English) — match the user's language — when **any** of the following conditions are met:

| Trigger condition | Typical phase |
| --- | --- |
| S2 + DBLP + CrossRef searches all return 0 results for a non-trivial query | discover Step 3-4 |
| Cite source chain fails completely (DBLP → CrossRef → S2 all miss) | cite Step 2 |
| 2+ consecutive API timeouts or HTTP errors across any scripts | any phase |
| Knowledge-gap search in discuss cannot find the referenced method/baseline | discuss Phase 3 |
| >30% of `\cite{}` references fail verification during write | write Step 4 |

**Behavior after trigger**: PUA pressure escalation forces exhaustive alternative strategies — rephrase keywords, broaden/narrow year range, try alternate APIs, decompose compound queries, search in adjacent fields — before accepting "not found." The escalation levels (L1→L4) and methodology follow the PUA skill's own protocol.

## Cross-Model Collaboration

Use a second LLM (via Codex MCP: `mcp__codex__codex`) throughout the lifecycle. The purpose is to **surface blind spots that a single model misses** and to create a three-way discussion (user + Claude + Codex) for richer exploration.

### Roles

Codex participates in three modes:

- **Co-thinker**: Divergent phases (brainstorming, discussion) — Codex contributes independent perspectives alongside Claude. The user gets two models' views to synthesize.
- **Adversarial reviewer**: Convergent phases (novelty check, reviewer simulation, final commit) — Codex challenges the direction, looking for weaknesses.
- **Cold reader**: Simplicity test — Codex receives minimal context to test whether the idea is self-explanatory.

### When to invoke

| # | Mode | Phase | What to send | What to ask |
| --- | --- | --- | --- | --- |
| 1 | Co-thinker | discuss Phase 2 (Assumption Surfacing) | Papers analyzed + field context from discover | "What assumptions does this field take for granted? What would break if each assumption were violated?" |
| 2 | Co-thinker | discuss Phase 3 (Discussion Loop) | Current discussion state (latest findings, open questions, proposed angles) | Phase 3-specific: varies per turn. See discuss.md for integration details. |
| 3 | Adversarial | discuss Phase 4 (Adversarial Novelty Check) | Proposed direction + closest existing work | "As a skeptical reviewer at {target venue}: (1) Is the claimed novelty real or superficial? (2) What existing work was missed? (3) What's the strongest argument against this direction?" |
| 4 | Adversarial | discuss Phase 5 (Reviewer Simulation) | Proposed direction + research brief so far | "Generate 3-4 specific reviewer objections. For each: the weakest claim, the missing baseline, the essential ablation, and severity (High/Medium/Low)." |
| 5 | Adversarial | discuss Phase 6 (Significance Test) | Proposed direction + significance analysis from Claude | "Evaluate this direction on three tiers: (1) real-world impact with concrete failure modes, (2) would the community think differently if this succeeds, (3) expected improvement magnitude vs. SOTA. Flag any tier that is weak." |
| 6 | Cold reader | discuss Phase 7 (Simplicity Test) | User's 2-sentence explanation ONLY — no research brief, no context | "Based only on these 2 sentences, explain back what the research idea is and what makes it novel. What is unclear or ambiguous?" |
| 7 | Adversarial | discuss Phase 8 (Experiment Design) | Completed experiment plan draft + research brief | "What baselines are missing? What essential ablation is not listed? Are there better-suited datasets? Is the expected results table realistic?" |
| 8 | Adversarial | discuss Phase 9 (Convergence Decision) | Complete research brief | "Given everything in this brief, would you recommend this direction for {target venue}? What is the single biggest risk? What would make you abandon this direction?" |
| 9 | Adversarial | write Step 5.5 (abstract + intro only) | Draft text + research brief | "As an AC at {target venue}: (1) Does the motivation hold up? (2) Is the contribution clearly distinguished from prior work? (3) What would make you desk-reject this?" |
| 10 | Adversarial | write related-work | Draft related-work section + discover results + read analyses | "As a reviewer: (1) What important related work is missing? (2) Is any prior work mischaracterized or unfairly compared? (3) Is the positioning of our contribution honest and precise?" |

### Protocol

1. Compose a focused prompt (see table above) with all relevant context. Do NOT pass the entire conversation history — send only the relevant artifacts.
2. Call `mcp__codex__codex` with the prompt.
3. For **co-thinker** mode: present Codex's ideas alongside Claude's, clearly labeled `[Codex]`. The user synthesizes both.
4. For **adversarial** mode: parse the response for **actionable concerns** (not stylistic preferences). Present labeled `[Cross-model review]`.
5. The user decides which concerns/ideas to act on.

### Phase 3 integration details

In the Discussion Loop, Codex participates as an ongoing third voice. The interaction model:
1. User raises a question or proposes a direction
2. Claude responds with analysis (infused with domain skill expertise)
3. Codex is consulted on the same question — **but phrased to elicit a different angle** (e.g., if Claude analyzed from a methodology perspective, ask Codex to consider from a practical/application perspective, or vice versa)
4. User sees both responses, picks what resonates, steers the next turn

**Not every turn requires Codex.** Use judgment:
- **Invoke Codex** when: the discussion hits a fork (multiple possible directions), a novel claim is made, the user questions a conclusion, or Claude is uncertain
- **Skip Codex** when: the turn is clarificational, the user is providing context, or the question is about a specific paper's content (domain skills + read phase handle this)

### What this is NOT

- **Not a score-chasing loop**: No "iterate until score ≥ N." That optimizes for LLM preferences, not research quality.
- **Not a rubber stamp**: If Codex finds nothing, that's a valid signal.
- **Not blocking**: If Codex MCP is unavailable, all phases proceed with Claude-only analysis (log warning). No phase is gated on Codex availability.

## Language

All output in English. For uncommon vocabulary (GRE-level), add Chinese translation in parentheses.

## Scripts

All scripts are in `skills/research/scripts/`. Key scripts:

### Search
| Script | Purpose |
| --- | --- |
| `s2_search.sh` | S2 relevance-ranked semantic search |
| `s2_bulk_search.sh` | S2 boolean bulk search with year filtering |
| `s2_batch.sh` | S2 batch metadata by paper IDs (NOT a search) |
| `s2_citations.sh` | Papers that cited a given paper |
| `s2_references.sh` | Papers cited by a given paper |
| `s2_recommend.sh` | Paper recommendations from positive/negative examples |
| `s2_snippet.sh` | Search within paper bodies for specific passages |
| `s2_match.sh` | Exact title match (single result) |
| `dblp_search.sh` | DBLP publication search |
| `dblp_bibtex.sh` | Fetch condensed BibTeX via DBLP search API (title + author + year) |
| `arxiv_bibtex.sh` | Fetch @misc BibTeX from arxiv.org (arXiv ID) |
| `crossref_search.sh` | CrossRef search (fallback) |
| `doi2bibtex.sh` | DOI → BibTeX via content negotiation |
| `hf_daily_papers.sh` | HF trending papers |

### Quality Evaluation
| Script | Purpose |
| --- | --- |
| `venue_info.sh` | Venue quality summary (CCF + IF + quartile) |
| `ccf_lookup.sh` | CCF ranking lookup |
| `if_lookup.sh` | Impact factor lookup |
| `author_info.sh` | Author h-index and stats |

### Config
| Script | Purpose |
| --- | --- |
| `init.sh` | Rate limit helpers, DBLP host fallback |

## Dependencies

### Required skills/plugins
- `high-agency` from `tanwei/pua` — pre-loaded at skill start
- `pua` / `pua-en` from `tanwei/pua` — pressure escalation when stuck (see PUA Pressure Escalation section for trigger conditions)
- `ml-paper-writing` from `Orchestra-Research AI-Research-SKILLs` — paper structure for write phase
- `brainstorming-research-ideas` from `Orchestra-Research AI-Research-SKILLs` — search strategy and ideation
- `creative-thinking-for-research` from `Orchestra-Research AI-Research-SKILLs` — cognitive frameworks for novel ideas
- All 21 domain skill categories from `Orchestra-Research AI-Research-SKILLs` — invoked via skill router (resolved through Claude Code's Skill tool)
- `humanizer` skill — style review for write phase
- `superpowers:dispatching-parallel-agents` — parallel search in discover phase
- `superpowers:verification-before-completion` — output verification in cite/write/discover phases

### Required MCP servers
- **Codex MCP** (`mcp__codex__codex`) — cross-model collaboration throughout the lifecycle (discuss Phases 2-9, write Step 5.5 + 5.6). See Cross-Model Collaboration section for all 10 invocation points. If Codex MCP is unavailable, all phases proceed with Claude-only analysis (log warning).

### Required API keys
- **Semantic Scholar**: set `S2_API_KEY` in `.claude/settings.local.json` under `"env"`. Get from: https://www.semanticscholar.org/product/api/api-key

### Optional API credentials
- **OpenReview**: set `OPENREVIEW_USER` and `OPENREVIEW_PASS` in `.claude/settings.local.json` under `"env"`. Register at: https://openreview.net/profile. Without these, OpenReview review/rebuttal data will not be fetched (all other features work normally).

### Installation prompt

If dependencies are missing on first use:

```
Before using /research, please ensure:

1. Install plugins:
   - tanwei/pua (provides high-agency, pua-en skills)
   - Orchestra-Research AI-Research-SKILLs (provides ml-paper-writing, brainstorming-research-ideas, creative-thinking-for-research, and 21 domain skill categories)
   - humanizer skill

2. Install hf CLI:
   curl -LsSf https://hf.co/cli/install.sh | bash -s

3. Set up API keys in your `.claude/settings.local.json`:
   ```json
   {
     "env": {
       "S2_API_KEY": "your-key-here",
       "OPENREVIEW_USER": "optional",
       "OPENREVIEW_PASS": "optional"
     }
   }
   ```
   - Semantic Scholar: https://www.semanticscholar.org/product/api/api-key
   - OpenReview (optional): https://openreview.net/profile
```

## Rate Limits

| Service | Limit | Strategy |
| --- | --- | --- |
| S2 | 1 req/sec (with key) | Sequential within agent, use batch/bulk |
| DBLP | ~1 req/sec | Sequential, 1s delay |
| CrossRef | No strict limit | Polite usage |
| HF CLI (`hf papers ls`) | No strict limit | Single calls |
| AlphaXiv curl | No strict limit | Respect 404s, no retry loop |
