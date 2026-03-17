---
name: research
description: Unified academic research lifecycle skill. Use for literature survey, paper reading, citation management, paper writing, and trend monitoring. Triggers on /research command.
---

# Research Skill

Full academic research lifecycle: discover, triage, read, cite, write, trending.

## Preload

On every invocation, before doing anything else:

1. **Load high-agency skill**: Invoke `pua:high-agency` to ensure exhaustive search and retry behavior
2. **Check AlphaXiv MCP**: Test if AlphaXiv MCP tools are available. If not, operate in degraded mode (see below)

## Entry Point

Parse user intent from `/research <args>` and route to the appropriate phase module.

| Input pattern                    | Phase flow              | Module                |
| -------------------------------- | ----------------------- | --------------------- |
| `/research survey "topic"`       | discover → triage → read | `phases/discover.md`  |
| `/research discover "topic"`     | discover                 | `phases/discover.md`  |
| `/research triage`               | triage                   | `phases/triage.md`    |
| `/research read 2401.12345`      | read                     | `phases/read.md`      |
| `/research read "paper title"`   | read                     | `phases/read.md`      |
| `/research cite 2401.12345`      | cite                     | `phases/cite.md`      |
| `/research cite "paper title"`   | cite                     | `phases/cite.md`      |
| `/research write <section>`      | write                    | `phases/write.md`     |
| `/research trending`             | trending                 | `phases/trending.md`  |
| Ambiguous input                  | Ask user to clarify      | —                     |

For `/research survey`, the full flow is: discover → present results → user selects → triage → user selects → read.

## Workspace

On first invocation, create `.research-workspace/` in the current working directory if it doesn't exist:

```bash
mkdir -p .research-workspace/sessions
echo '{"sessions": [], "current_session": null}' > .research-workspace/state.json
```

Each survey creates a session: `.research-workspace/sessions/{topic-slug}-{date}/`

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

## Degraded Mode

If AlphaXiv MCP is unavailable:
- **Discover**: S2 + HF agents only (2 of 3)
- **Triage**: `curl -s "https://alphaxiv.org/overview/{ID}.md"` as fallback
- **Read**: `curl -s "https://alphaxiv.org/abs/{ID}.md"`, then arXiv PDF
- **Trending**: HF daily papers only, AlphaXiv source skipped

## Timeout Policy

Each parallel search agent has a 60-second timeout. If an agent times out or errors, proceed with results from the remaining agents. Log the failure but do not block.

## Iron Rules

1. **Zero hallucination citations** — every citation from an API call, never from model memory
2. **BibTeX priority** — DBLP > CrossRef > S2 (AlphaXiv is content-only, not a citation source)
3. **High-agency preload** — loaded at skill start, drives exhaustive search and retry
4. **Quality gate** — no paper presented to user without quality evaluation
5. **Source tracing** — every citation tagged with data source ("via DBLP", "via CrossRef", etc.)
6. **Own model for analysis** — never rely on AlphaXiv's AI-generated answers; use their content extraction, analyze with own Claude

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
| `dblp_bibtex.sh` | Fetch BibTeX from DBLP key |
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
| `init.sh` | Environment loading, rate limit helpers |

## Dependencies

### Required skills/plugins
- `high-agency` from `tanwei/pua` — pre-loaded at skill start
- `pua-en` from `tanwei/pua` — pressure escalation when stuck
- `ml-paper-writing` from `Orchestra-Research AI-Research-SKILLs` — paper structure for write phase
- `humanizer` skill — style review for write phase

### Required MCP servers (user must configure)
- **AlphaXiv MCP**: endpoint `https://api.alphaxiv.org/mcp/v1` (SSE + OAuth 2.0)
- **HF MCP**: Hugging Face integration

### Required API keys
- **Semantic Scholar**: save `S2_API_KEY` in `skills/research/.env`. Get from: https://www.semanticscholar.org/product/api/api-key

### Installation prompt

If dependencies are missing on first use:

```
Before using /research, please ensure:

1. Install plugins:
   - tanwei/pua (provides high-agency, pua-en skills)
   - Orchestra-Research AI-Research-SKILLs (provides ml-paper-writing)
   - humanizer skill

2. Configure MCP servers:
   - AlphaXiv MCP: endpoint https://api.alphaxiv.org/mcp/v1 (SSE + OAuth)
   - HF MCP: Hugging Face integration

3. Set up API keys:
   - Semantic Scholar: save S2_API_KEY in skills/research/.env
     Get key at: https://www.semanticscholar.org/product/api/api-key
```

## Rate Limits

| Service | Limit | Strategy |
| --- | --- | --- |
| S2 | 1 req/sec (with key) | Sequential within agent, use batch/bulk |
| DBLP | ~1 req/sec | Sequential, 1s delay |
| CrossRef | No strict limit | Polite usage |
| HF API | No strict limit | Single calls |
| AlphaXiv MCP | Unknown | Respect errors |
