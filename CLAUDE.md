# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Context

**scholar-tools** is a Claude Code plugin that provides an academic research lifecycle through a single `/research` command. It covers literature discovery, deep discussion/ideation, paper reading, citation management, paper writing, and trend monitoring.

The central innovation is a **Skill Router** that maps paper content to 21 domain skill categories (from Orchestra-Research/AI-Research-SKILLs), injecting expert knowledge into every phase. Every citation must trace to an API call — never to model memory.

This is a **Claude Code plugin** (not a standalone app). It runs inside Claude Code's plugin system and uses bash scripts for all API interactions (Semantic Scholar, DBLP, CrossRef, arXiv, HuggingFace, AlphaXiv, OpenReview).

## Commands

```bash
# Run all tests (hits live APIs, requires S2_API_KEY in .claude/settings.json env)
bash tests/run_all_tests.sh

# Run a single test suite
bash tests/test_s2_search.sh

# Run a single script manually
bash skills/research/scripts/s2_search.sh "human pose estimation" 10

# Structural validation only (no API calls)
bash tests/test_structure.sh
```

No build step. No package manager. All scripts are plain bash with `curl`, `jq`, and `sqlite3` as external dependencies.

## Architecture

### Plugin entry point

`skills/research/SKILL.md` — YAML-frontmatter skill file. Claude Code loads this when `/research` is invoked. It parses user intent and routes to phase modules.

### Phase modules (`skills/research/phases/`)

Each phase is a `.md` file with structured instructions that Claude follows as a workflow:

| Phase | File | Key behavior |
|-------|------|-------------|
| discover | `discover.md` | Parallel S2 + HF search → dedup → quality-rank → quick-read → landscape summary |
| discuss | `discuss.md` | 9-sub-phase ideation engine with adversarial checks and Codex co-thinking |
| read | `read.md` | Deep structured analysis with domain expert perspective |
| cite | `cite.md` | DBLP > CrossRef > S2 BibTeX chain (zero hallucination) |
| write | `write.md` | Paper writing with Triple Review Gate + Consistency Check |
| trending | `trending.md` | Personalized daily paper digest |
| skill-router | `skill-router.md` | Maps paper keywords → 21 domain categories → loads relevant skills |

### Scripts (`skills/research/scripts/`)

19 self-contained bash scripts. Each:
- Starts with `set -e`
- Sources `init.sh` for rate limiting, API keys, and DBLP host fallback
- Uses `curl -sL -w "\n%{http_code}"` for all HTTP calls
- Outputs JSON to stdout, errors as JSON to stderr
- Exits 0 on success, 1 on error (never silent empty output)

`init.sh` is the shared foundation: it resolves `$SKILL_ROOT`, exports data directory paths, provides `rate_limit()` and `dblp_request()` helpers.

### Data (`skills/research/data/`)

- `ccf_2026.sqlite` — CCF venue rankings (682 entries)
- `impact_factor.sqlite3` — journal impact factors (19,727 entries)
- `ccf_2026.jsonl` — source data for CCF database

### Workspace (runtime, gitignored)

`.research-workspace/` is created at invocation time in the user's project directory. Stores session results, paper caches, checkpoints, and verified BibTeX.

## Development Standards

All conventions below are derived from real bugs. See `CONTRIBUTING.md` for the full rationale and examples behind each rule.

### curl

- Always `-sL` (never bare `-s` — missing `-L` silently breaks on redirects)
- Always `-w "\n%{http_code}"` to capture HTTP status; parse status before piping to jq
- Always `--max-time` for timeout safety
- Never detect errors by grepping response body — use HTTP status codes
- Never `2>/dev/null` on entire pipelines — only on the curl call itself

### jq

- `//` (alternative operator) does NOT catch empty strings. `"" // "N/A"` evaluates to `""`. Use explicit `if . == "" or . == null then "N/A" else . end`
- Verify API response structure by calling the real API, not guessing from docs
- Check array length BEFORE slicing (not after)
- Handle single-element vs array ambiguity (DBLP returns object for 1 author, array for multiple)

### Error handling

- Empty stdout with exit 0 is a bug — always output an error message or exit non-zero
- All error messages to stderr as JSON: `echo '{"error": "description"}' >&2`
- Non-JSON error responses (HTML error pages) break jq silently — validate HTTP status BEFORE piping

### Testing

- Every script must have a test in `tests/`
- Tests hit live APIs — they require `S2_API_KEY` (set in `.claude/settings.json` `env`, auto-exported by Claude Code)
- Test fixtures must be verified against real API responses (not assumed)
- Content assertions required — checking field existence alone is insufficient
- Test the test: break the script, confirm the test catches it

### Iron Rules (enforced in all phases)

1. Zero hallucination citations — every citation from an API call
2. BibTeX priority — DBLP > CrossRef > S2
3. PUA pressure escalation when stuck (exhaustive retry before "not found")
4. Quality gate — no paper presented without venue/citation evaluation
5. Source tracing — every citation tagged with data source
6. Own model for analysis — never rely on AlphaXiv's AI summaries
7. Domain skill grounding — claims trace to paper content, not skill assertions
8. Adversarial before commitment — novelty check before finalizing direction
9. Multi-perspective review for framing — abstract/intro pass three perspectives
10. Simplicity preference — prefer simpler approach when merit is similar
11. Verify before completion — run verification before claiming output is done
12. Root cause before retry — diagnose failures before retrying

### Cross-model collaboration

Codex (via `mcp__codex__codex`) participates as co-thinker (divergent phases) and adversarial reviewer (convergent phases). Every Codex call follows the 6-element Delegation Contract (WHY/WHAT/WHERE/LIMIT/DONE/DON'T). Codex is never blocking — all phases work Claude-only if MCP is unavailable.

### Pre-push checklist

1. Static analysis: verify all curl/jq patterns match the standards above
2. Run each modified script with real inputs and inspect output
3. Run full test suite: `bash tests/run_all_tests.sh`
4. Cross-validate any empty or suspicious output with raw curl
5. Break modified scripts and verify their tests catch the bug
