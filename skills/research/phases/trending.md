# Trending Phase

Curated digest of trending papers personalized to the user's research interests.

## Trigger

Called when user invokes `/research trending`.

## Workflow

### Step 1: Fetch trending papers from multiple sources

**Source 1: HF Daily Papers**

```bash
bash scripts/hf_daily_papers.sh 30
```

Returns papers with title, arxiv_id, summary, upvotes, comments, github info.

### Step 2: Deduplicate

Deduplicate results by arXiv ID (in case the same paper appears in multiple pages).

### Step 3: Personalization filter

Tag each paper based on user's research profile:

| Tier   | Criteria                                                                 |
| ------ | ------------------------------------------------------------------------ |
| High   | pose estimation, low-visibility, AIGC, VLM/MLLM, multimodal, emotion    |
| Medium | general CV, image generation, video understanding, robotics + vision     |
| Low    | pure text LLM, NLP-only, non-vision tasks                               |

Matching logic:
- Check title + summary keywords against tier definitions
- If paper mentions multiple areas, use the highest matching tier
- Default to "Medium" if no clear match

Sort: High-relevance first, then Medium, then Low. Within each tier, sort by upvotes (descending).

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

### Step 4: Present digest

For each paper:

```
[HIGH] Title (date)
Authors: first 3
Summary: 1-2 sentences (from HF AI summary or own analysis)
Relevance: why this matches your interests
Upvotes: N | Comments: N | GitHub: stars if available
Link: https://alphaxiv.org/overview/{arxiv_id}
Connection: how this could relate to your current work (high-tier only)
```

Group by tier with headers:
- **Highly relevant to your research**
- **Potentially interesting**
- **Other trending papers**

### Step 5: Follow-up options

After presenting the digest:
- "Want to read any of these in detail?" → route to read phase
- "Want to cite any of these?" → route to cite phase
- "Want to do a deeper survey on [topic from trending]?" → route to discover phase
