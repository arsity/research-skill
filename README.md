# research-skill

A Claude Code plugin for academic research with domain-aware skill routing. `/research discover "topic"` searches multiple databases in parallel, ranks papers by venue quality and citations, quick-reads the top results, and provides a landscape summary. `/research discuss` drives deep research ideation with adversarial novelty checks and reviewer simulation. `/research cite` generates verified BibTeX. Every citation traces to an API call, never to model memory.

<p>
  <img src="https://img.shields.io/badge/Claude_Code-black?style=flat-square&logo=anthropic&logoColor=white" alt="Claude Code">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
</p>

## What it does

| Command | What happens |
|---------|-------------|
| `/research discover "topic"` | S2 semantic search + HF daily papers, deduplicate, quality-rank, quick-read top papers (via AlphaXiv curl), generate landscape summary |
| `/research discuss` | Deep discussion: assumption surfacing, adversarial novelty check, reviewer simulation, significance test, experiment design |
| `/research discuss <paper>` | Start discussion from a specific paper |
| `/research read <paper>` | Deep structured analysis with domain expert perspective |
| `/research cite <paper>` | Verified BibTeX via DBLP > CrossRef > S2 chain |
| `/research write <section>` | Write a paper section with Triple Review Gate (abstract/intro) + Consistency Check (method/experiments/conclusion) |
| `/research trending` | Personalized digest of today's trending papers with domain skill insights |

All commands support `--domain <categories>` (additive) or `--domain-only <categories>` (exclusive) to override auto-detected domain skills.

## Skill Router

The central innovation: a **Skill Router** maps paper content to 21 domain skill categories from [Orchestra-Research/AI-Research-SKILLs](https://github.com/Orchestra-Research/AI-Research-SKILLs), injecting expert knowledge into each phase.

| # | Category | Example Skills |
|---|----------|---------------|
| 1 | Model-Architecture | litgpt, mamba, nanogpt, rwkv, torchtitan |
| 2 | Tokenization | huggingface-tokenizers, sentencepiece |
| 3 | Fine-Tuning | axolotl, llama-factory, peft, unsloth |
| 4 | Mechanistic-Interpretability | transformer-lens, saelens, pyvene, nnsight |
| 5 | Data-Processing | ray-data, nemo-curator |
| 6 | Post-Training | trl, grpo-rl-training, openrlhf, simpo, verl |
| 7 | Safety-Alignment | constitutional-ai, llamaguard, nemo-guardrails |
| 8 | Distributed-Training | megatron-core, deepspeed, pytorch-fsdp2, accelerate |
| 9 | Infrastructure | modal, skypilot, lambda-labs |
| 10 | Optimization | flash-attention, bitsandbytes, gptq, awq, hqq, gguf |
| 11 | Evaluation | lm-evaluation-harness, bigcode-evaluation-harness |
| 12 | Inference-Serving | vllm, tensorrt-llm, llama.cpp, sglang |
| 13 | MLOps | weights-and-biases, mlflow, tensorboard |
| 14 | Agents | langchain, llamaindex, crewai, autogpt |
| 15 | RAG | chroma, faiss, sentence-transformers, pinecone, qdrant |
| 16 | Prompt-Engineering | dspy, instructor, guidance, outlines |
| 17 | Observability | langsmith, phoenix |
| 18 | Multimodal | clip, whisper, llava, stable-diffusion, segment-anything |
| 19 | Emerging-Techniques | moe-training, model-merging, long-context, speculative-decoding |
| 20 | ML-Paper-Writing | ml-paper-writing (auto-invoked in write phase) |
| 21 | Research-Ideation | brainstorming-research-ideas, creative-thinking-for-research |

The router auto-detects relevant categories from paper keywords and classifies them as **primary** (core contribution) or **secondary** (peripheral tool).

## How search works

Two agents run in parallel, each with a 60-second timeout:

1. **Semantic Scholar** — semantic search across 200M+ papers (`s2_search.sh`) + boolean bulk search (`s2_bulk_search.sh`) with year filtering. Primary search source.
2. **Hugging Face** — `hf papers ls` daily/trending papers filtered by topic keywords. Complements S2 by surfacing recent community-highlighted work that may not yet have citations.

Results are deduplicated by arXiv ID / DOI / title similarity, then scored:

| Signal | Weight |
|--------|--------|
| CCF ranking (A/B/C) | base score |
| JCR/CAS quartile | base score |
| Impact factor | 30% |
| Citation count (log-scaled) | 20% |
| Recency | 10% |
| First-author h-index | 10% |

arXiv-only papers with < 100 citations get a -20 penalty. Published versions are preferred.

After scoring, each top paper is **quick-read** via `curl -sL https://alphaxiv.org/overview/{id}.md` (or S2 abstract if not on arXiv) and receives a verdict: Must read / Worth reading / Skim / Skip. A **landscape summary** synthesizes key themes and trends.

## How discussion works

The discuss phase is a 9-sub-phase ideation engine:

1. **Setup** — load discover/read results, invoke skill router + research-ideation skills
2. **Assumption Surfacing** — challenge inherited conventions in the field
3. **Discussion Loop** — iterative analysis with auto knowledge gap filling and out-of-domain search
4. **Adversarial Novelty Check** — verify proposed directions against existing literature
5. **Reviewer Simulation** — generate specific reviewer objections with severity ratings
6. **Significance Test** — 3-tier assessment (real-world impact, community impact, improvement magnitude)
7. **Simplicity Test** — can the idea be explained in 2 sentences without jargon?
8. **Experiment Design** — baselines, datasets, ablations, expected results, compute requirements
9. **Convergence Decision** — direction comparison matrix backed by evidence

Output: a structured **research brief** (`brief.json`) that feeds into the write phase.

## How citations work

Zero hallucination policy. Every BibTeX entry must trace to an API response. The chain:

```
1. DBLP search → title match (>90% token overlap)
   → If published venue: fetch condensed .bib                          → "via DBLP"
   → If arXiv-only (CoRR): fetch from arxiv.org instead               → "via arXiv"
2. CrossRef search → extract DOI → content negotiation                 → "via CrossRef"
3. S2 exact match → construct from metadata (or arXiv if available)    → "via S2 — verify manually"
4. All fail → "Citation source not verified. Not safe to cite."
```

Never generates BibTeX from model memory. Never fills in year/venue/authors from model knowledge.

## How writing works

The write phase adds two quality mechanisms:

- **Triple Review Gate** (abstract + introduction): Three perspectives (Reviewer, AC/SAC, Senior Researcher) each provide 2-3 specific revision suggestions
- **Consistency Check** (method, experiments, conclusion): Cross-reference scan ensures contributions match experiments, claims match results, assumptions match setup

## Installation

### Claude Code

```bash
# Option 1: Install via marketplace
claude plugin marketplace add arsity/research-skill
claude plugin install research-skill@research-skill

# Option 2: Manual install
git clone https://github.com/arsity/research-skill.git ~/.claude/plugins/research-skill
```

### Prerequisites

**Required:**

1. **Semantic Scholar API key** — get one at [semanticscholar.org/product/api](https://www.semanticscholar.org/product/api/api-key), then add to your project's `.claude/settings.json`:
   ```json
   {
     "env": {
       "S2_API_KEY": "your-key-here"
     }
   }
   ```
   Claude Code automatically exports `env` entries as environment variables — scripts read `$S2_API_KEY` directly.

2. **Required plugins:**
   - `tanwei/pua` — provides `pua` and `pua-en` skills
   - `Orchestra-Research/AI-Research-SKILLs` — provides `ml-paper-writing`, `brainstorming-research-ideas`, `creative-thinking-for-research`, and 21 domain skill categories
   - A `humanizer` skill for style review during paper writing

3. **hf CLI** — for fetching HF daily/trending papers:
   ```bash
   curl -LsSf https://hf.co/cli/install.sh | bash -s
   ```

## Project structure

```
skills/research/
  SKILL.md                  # Orchestrator — intent detection + routing + unified input parsing
  phases/
    skill-router.md         # Central domain detection + skill routing (21 categories)
    discover.md             # Multi-source search + quick-read + landscape summary
    discuss.md              # 9-phase ideation engine with adversarial checks
    read.md                 # Deep structured analysis with domain expert perspective
    cite.md                 # DBLP > CrossRef > S2 BibTeX chain
    write.md                # Paper writing with Triple Review Gate + Consistency Check
    trending.md             # Personalized trending digest with domain insights
  scripts/                  # 19 self-contained bash scripts
    init.sh                 # Rate limit helpers, DBLP host fallback
    s2_search.sh            # S2 relevance-ranked search
    s2_bulk_search.sh       # S2 boolean bulk search with year filtering
    s2_batch.sh             # S2 batch metadata (up to 500 IDs)
    s2_citations.sh         # Citation graph traversal
    s2_references.sh        # Reference graph traversal
    s2_recommend.sh         # Paper recommendations
    s2_snippet.sh           # Search within paper bodies
    s2_match.sh             # Exact title match
    dblp_search.sh          # DBLP publication search
    dblp_bibtex.sh          # Title+author+year → condensed .bib via DBLP API
    arxiv_bibtex.sh         # arXiv ID → @misc .bib from arxiv.org
    crossref_search.sh      # CrossRef search
    doi2bibtex.sh           # DOI → BibTeX via content negotiation
    hf_daily_papers.sh      # HF trending papers API
    venue_info.sh           # Venue quality summary (CCF + IF + quartile)
    ccf_lookup.sh           # CCF ranking lookup
    if_lookup.sh            # Impact factor lookup
    author_info.sh          # Author h-index and stats
  data/
    ccf_2026.sqlite         # CCF rankings database (682 entries)
    ccf_2026.jsonl          # CCF rankings source
    impact_factor.sqlite3   # Impact factor database (19,727 journals)
  tests/                    # 9 test suites + runner
    run_all_tests.sh
    test_structure.sh       # Structural validation (phase files, categories, migrations)
    test_s2_search.sh
    test_s2_network.sh
    test_s2_batch.sh
    test_dblp.sh
    test_crossref.sh
    test_quality_eval.sh
    test_hf_daily.sh
    test_cite_chain.sh
```

## Running tests

```bash
bash skills/research/tests/run_all_tests.sh
```

Requires `S2_API_KEY` in `.claude/settings.json` `env` (see Installation). Tests hit live APIs (S2, DBLP, CrossRef, HF).

## Workspace

On first invocation, `/research` creates `.research-workspace/` in the current directory. Each session persists discover results, discussion briefs, read analyses, and verified BibTeX — all as JSON for reuse across phases.

```
.research-workspace/
  state.json
  sessions/
    {topic-slug}-{date}/
      discover.json           # Search results + verdicts + landscape summary
      discuss/
        brief.json            # Research brief from discuss phase
      read/{paper_id}.json    # Structured paper analyses
      cite/{paper_id}.bib     # Verified BibTeX entries
      cite/cite-log.json      # Citation metadata and sources
```

## Iron Rules

1. **Zero hallucination citations** — every citation from an API call, never from model memory
2. **BibTeX priority** — DBLP > CrossRef > S2
3. **PUA pressure escalation** — invoke `pua`/`pua-en` when stuck, drives exhaustive search and retry
4. **Quality gate** — no paper presented without quality evaluation
5. **Source tracing** — every citation tagged with data source
6. **Own model for analysis** — never rely on AlphaXiv's AI-generated answers
7. **Domain skill grounding** — factual claims must trace to paper content, not skill-generated assertions
8. **Adversarial before commitment** — no direction finalized without novelty check
9. **Triple review for framing** — abstract and introduction must pass three review perspectives
10. **Simplicity preference** — between two approaches of similar merit, prefer the simpler one

## Rate limits

| Service | Limit | Strategy |
|---------|-------|----------|
| Semantic Scholar | 1 req/sec (with key) | Sequential + batch/bulk endpoints |
| DBLP | ~1 req/sec | Sequential, 1s delay |
| CrossRef | 50 req/sec | Polite pool |
| HF CLI / AlphaXiv curl | No strict limit | Respectful usage |

## License

[MIT](LICENSE) — Luke (Haopeng Chen)
