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

### Step 3: Parallel search — dispatch three agents

Launch three search agents in parallel. Each has a 60-second timeout. If an agent errors or times out, proceed with results from the others.

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

**Agent 2: AlphaXiv MCP**

Use AlphaXiv MCP tools (if available):
- `embedding_similarity_search` with the query for semantic search
- `full_text_papers_search` with key terms for keyword search

If AlphaXiv MCP is unavailable, skip this agent (degraded mode).

**Agent 3: Hugging Face MCP**

Use HF MCP tool:
- `mcp__claude_ai_Hugging_Face__paper_search` with the query (returns up to 12 results)

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
  "source": "s2|alphaxiv|hf",
  "found_in": ["s2", "alphaxiv"]
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

### Step 6: Quick-read (absorbed from triage)

For top N papers by composite score (highest first):

**For arXiv papers:**

1. Try AlphaXiv MCP `get_paper_content` (report/overview mode)
2. If MCP unavailable: `curl -s "https://alphaxiv.org/overview/{arxiv_id}.md"`
3. If alphaxiv returns 404: use S2 abstract from discover results

**For non-arXiv papers (conference-only):**

1. Check S2 `openAccessPdf` URL from discover results
2. If available: download and read the PDF directly
3. If not: resolve DOI to publisher page:
   - CVF Open Access for CVPR/ICCV/ECCV papers
   - ACM Digital Library for ACM papers
   - IEEE Xplore for IEEE papers
4. Read the paper's abstract and introduction

For each paper, generate:
- **Core contribution**: one sentence summarizing what this paper adds
- **Read recommendation**: "Must read" / "Worth reading" / "Skim" / "Skip"
- **Domain assessment**: invoke matched domain skill (from Step 1's router result) for domain-specific relevance assessment

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
    "source": "s2|alphaxiv|hf", "found_in": ["s2", "alphaxiv"],
    "score": 85.3,
    "verdict": "must_read",
    "core_contribution": "...",
    "domain_assessment": "..."
  }]
}
```

### Step 10: Expansion options

After presenting results, offer the user:
- "Want to find papers that cite [paper X]?" → `s2_citations.sh`
- "Want to trace references of [paper X]?" → `s2_references.sh`
- "Want recommendations based on these papers?" → `s2_recommend.sh` with top paper IDs as positives
- "Ready to discuss?" → proceed to discuss phase
