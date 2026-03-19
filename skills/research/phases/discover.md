# Discover Phase

Broad field scan: search → triage → quick-read → landscape report.

## Trigger

Called when user invokes `/research discover "topic"`.

## Workflow

### Step 1: Parse query + invoke skill router

Extract the user's research query. If ambiguous, ask one clarifying question before proceeding.

Invoke the skill router with:
- Input: `topic_description` = user's query
- Phase type: `discover`
- Apply `--domain` / `--domain-only` if user specified

The router returns primary domain categories (top 1-2) + `research-ideation` for search strategy.

### Step 2: Search strategy

Invoke `research-ideation` skill (`brainstorming-research-ideas`) to generate diversified search queries from the user's topic. This produces multiple angles and keyword variations to improve search coverage.

### Step 3: Parallel search — dispatch via `superpowers:dispatching-parallel-agents`

Invoke `superpowers:dispatching-parallel-agents` to launch two independent search agents. Each has a 60-second timeout. If an agent errors or times out, proceed with results from the other.

**Agent 1: Semantic Scholar**

Run sequentially (1 req/sec rate limit):

```bash
bash scripts/s2_search.sh "<query>" 20
```

If the user specifies a year range or boolean operators, also run:

```bash
bash scripts/s2_bulk_search.sh "<query>" "<year_range>" 50
```

Each result includes `paper_id`, `title`, `year`, `venue`, `citations`, `doi`, `arxiv_id`, `source: "s2"`.

**Agent 2: Hugging Face (trending complement)**

Fetch today's community-highlighted papers and filter by topic keywords:

```bash
hf papers ls --format json
```

Filter results: match paper title/summary against the user's query keywords. This is NOT a semantic search — it returns recent daily/trending papers only. It complements S2 by surfacing new work with community traction (upvotes, GitHub stars) that may not yet have citations in S2.

**Why `superpowers:dispatching-parallel-agents`**: The two agents are fully independent (no shared state, different APIs), making them ideal for parallel dispatch. The superpowers skill handles agent lifecycle, timeout enforcement, and partial-failure aggregation — no need to reimplement this logic.

### Step 4: Merge

Receive results from all agents. Deduplicate:
1. By arXiv ID (exact match)
2. By DOI (exact match)
3. By title similarity (>85% word-level overlap, case-insensitive)

Normalize all results to a common format:
```json
{
  "paper_id": "s2_id or arxiv_id",
  "title": "...",
  "year": 2024,
  "venue": "...",
  "citations": 123,
  "doi": "...",
  "arxiv_id": "...",
  "authors": [{"name": "...", "id": "..."}],
  "source": "s2|hf",
  "found_in": ["s2", "hf"]
}
```

### Step 5: Quality evaluation

For each paper in the merged list:

1. **Batch metadata**: Run `s2_batch.sh` with all paper IDs to fill missing metadata (citation counts, venues, author IDs). Chunk into groups of 500 max.

2. **Venue quality**: For each unique venue, run:
   ```bash
   bash scripts/venue_info.sh "<venue>"
   ```
   This returns CCF rank, JCR quartile, CAS quartile, impact factor.

3. **Author quality**: For first author of each paper (where author ID is available):
   ```bash
   bash scripts/author_info.sh "<author_id>"
   ```

4. **arXiv classification**:
   - `recommended`: arXiv paper with citations >= 100
   - `caution`: arXiv paper with citations < 100
   - `normal`: formally published (not arXiv)

5. **Composite score**:

   | Dimension       | Weight | Calculation                       |
   | --------------- | ------ | --------------------------------- |
   | CCF ranking     | base   | A=100, B=70, C=40                 |
   | JCR quartile    | base   | Q1=80, Q2=60, Q3=40, Q4=20       |
   | CAS quartile    | base   | 1=90, 2=70, 3=50, 4=30           |
   | Impact factor   | 30%    | IF * 5 (cap 50)                   |
   | Citation count  | 20%    | log10(citations+1) * 10 (cap 50) |
   | Year            | 10%    | max(0, (year-2015) * 2) (cap 30) |
   | Author h-index  | 10%    | first author h-index * 2 (cap 30) |

   ```
   base_score = max(CCF, JCR, CAS)        # highest applicable base, 0 if none
   weighted   = IF*0.3 + citations*0.2 + year*0.1 + h_index*0.1
   penalty    = -20 if (arXiv AND citations < 100) else 0
   total      = base_score + weighted + penalty
   ```

### Step 6: Quick-read (cache-aware)

For top N papers by composite score (highest first):

**Check cache first**: For each paper, check `.research-workspace/sessions/{slug}/cache/{paper_id}/cache_meta.json`. If `overview.md` is cached, use it directly. See Paper Cache in SKILL.md.

**On cache miss for arXiv papers:**

1. `curl -sL "https://alphaxiv.org/overview/{arxiv_id}.md"` → save to `cache/{paper_id}/overview.md`
2. `curl -sL "https://alphaxiv.org/abs/{arxiv_id}.md"` → save to `cache/{paper_id}/fulltext.md` (if overview is 404 or more detail needed)
3. If both return 404: use S2 abstract from discover results

**On cache miss for non-arXiv papers (conference-only):**

1. Check S2 `openAccessPdf` URL from discover results
2. If available: download and read the PDF → save to `cache/{paper_id}/paper.pdf`
3. If not: resolve DOI to publisher page:
   - CVF Open Access for CVPR/ICCV/ECCV papers
   - ACM Digital Library for ACM papers
   - IEEE Xplore for IEEE papers
4. Read the paper's abstract and introduction

Update `cache_meta.json` after each fetch. Skip full OpenReview fetch during quick-read (too heavy for batch processing).

For each paper, generate:
- **Core contribution**: one sentence summarizing what this paper adds
- **Read recommendation**: "Must read" / "Worth reading" / "Skim" / "Skip"
- **Domain assessment**: invoke matched domain skill (from Step 1's router result) for domain-specific relevance assessment

### Step 6.5: Verification gate (`superpowers:verification-before-completion`)

Before presenting results to the user, invoke `superpowers:verification-before-completion` to confirm:
- Every paper in the output has a composite score (no missing quality evaluations)
- No duplicate papers slipped through deduplication (re-check arXiv ID / DOI / title overlap)
- Core contribution and read recommendation are populated for all quick-read papers
- At least one search source returned results (if both returned 0, trigger PUA escalation per Iron Rule)

Only proceed to presentation after all checks pass.

### Step 7: Present ranked results

Sort by composite score (descending). For each paper:

```
1. [Must read] Title (Year) — Venue
   Authors (first 3)
   Core contribution: one sentence
   Citations: N | Quality: CCF-A / Q1 | Score: X.X
   Domain insight: domain-specific assessment from skill
```

### Step 8: Landscape summary

Synthesize a 1-paragraph overview of the field based on all discovered papers:
- Key themes and dominant approaches
- Recent trends (last 1-2 years)
- Notable gaps or underexplored directions
- Where the user's interest fits in the landscape

### Step 9: Save to workspace

Save results to `.research-workspace/sessions/{topic-slug}-{date}/discover.json`:
```json
{
  "query": "...",
  "timestamp": "...",
  "landscape_summary": "...",
  "skills_invoked": ["..."],
  "total_found": 42,
  "results": [{
    "paper_id": "...", "title": "...", "year": 2024, "venue": "...",
    "citations": 123, "doi": "...", "arxiv_id": "...",
    "authors": [{"name": "...", "id": "..."}],
    "source": "s2|hf", "found_in": ["s2", "hf"],
    "score": 85.3,
    "verdict": "must_read",
    "core_contribution": "...",
    "domain_assessment": "..."
  }]
}
```

### Step 9.5: Checkpoint

Write checkpoint to `checkpoints/discover_{timestamp}.json` with status `completed`, referencing `discover.json` as the primary artifact. Include: query, total papers found, number of must-read/worth-reading/skim/skip verdicts, skills invoked.

### Step 10: Expansion options

After presenting results, offer the user:
- "Want to find papers that cite [paper X]?" → `s2_citations.sh`
- "Want to trace references of [paper X]?" → `s2_references.sh`
- "Want recommendations based on these papers?" → `s2_recommend.sh` with top paper IDs as positives
- "Ready to discuss?" → proceed to discuss phase
