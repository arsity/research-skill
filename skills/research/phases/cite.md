# Cite Phase

Verified BibTeX generation with strict source chain. Zero hallucination policy.

## Trigger

Called via `/research cite 2401.12345` or `/research cite "paper title"`, or automatically during write phase for every `\cite{}`.

## Iron Rules

1. **Every citation must trace to an API call response** — never from model memory
2. **Never generate BibTeX from model memory** — always fetch from external source
3. **Never fill in metadata from model knowledge** — year, venue, authors must come from API
4. **If all sources fail** — report "unverified source — not safe to cite", do not guess

## Workflow

### Step 1: Resolve paper identity

Use unified input parsing (defined in SKILL.md):
- arXiv ID → search by ID
- DOI → use directly for CrossRef
- Free text → `s2_match.sh` exact match first, then `s2_search.sh` + `dblp_search.sh` with clarify flow if multiple candidates

### Step 2: BibTeX source chain

Execute in order. Stop at the first success.

```
0a. CVF Open Access (golden standard for CVPR/ICCV/WACV, 2013+)
   → Prerequisite: Step 1 must have confirmed venue and year first
   → Only if venue matches CVPR, ICCV, or WACV and year >= 2013
   → python3 scripts/cvf_bibtex.py "<title>" "<author_token>" "<CONF>" "<year>"
   → author_token: the surname token CVF uses in the filename — typically the first
     author's last name, but occasionally the presenter or submitting author.
     For compound names like "Rota Bulo", use the last token ("Bulo").
   → If CVF returns BibTeX: cross-check with DBLP (see CVF cross-check below)
   → Tag: "via CVF ✓ (DBLP cross-checked)" or "via CVF ✓"

0b. NeurIPS Proceedings (golden standard for NeurIPS/NIPS, 1987+)
   → Prerequisite: Step 1 must have confirmed venue and year first
   → Only if venue matches NeurIPS or NIPS (main conference or Datasets &
     Benchmarks track — NOT workshops)
   → python3 scripts/neurips_bibtex.py "<title>" "<year>"
   → Two-source strategy (handled internally by the script):
     • papers.nips.cc: official proceedings (1987–2024), richer BibTeX
       (author, booktitle, editor, pages, publisher, volume, year)
       Includes Datasets & Benchmarks track from 2022+.
     • datasets-benchmarks-proceedings.neurips.cc: D&B track 2021
       (separate site, same URL pattern and BibTeX quality)
     • OpenReview API v2: fallback for recent years not yet on nips.cc
       (title, author, booktitle, year, url)
       Includes NeurIPS 2023+ main conference and D&B track.
   → Script outputs source to stderr: "source: nips.cc" or "source: OpenReview"
   → If BibTeX returned: cross-check with DBLP (see NeurIPS cross-check below)
   → Tag: "via NeurIPS proceedings ✓ (DBLP cross-checked)" or
     "via NeurIPS proceedings ✓" or "via OpenReview ✓ (DBLP cross-checked)"

0c. ICLR Proceedings (golden standard for ICLR, 2021+)
   → Prerequisite: Step 1 must have confirmed venue and year first
   → Only if venue matches ICLR (main conference — NOT workshops)
   → python3 scripts/iclr_bibtex.py "<title>" "<year>"
   → Dual-API strategy (OpenReview):
     • ICLR 2024+: OpenReview API v2 (api2.openreview.net)
     • ICLR 2021-2023: OpenReview API v1 (api.openreview.net)
     • ICLR 2018-2020: No reliable acceptance data — use DBLP instead
     • Acceptance filtering (CRITICAL — triple-layer):
       1. venueid == "ICLR.cc/{year}/Conference" exact match
       2. venue string allowlist: must match "ICLR YYYY Poster/Oral/Spotlight"
       3. BibTeX type must be @inproceedings (not @misc)
     • Rejected, withdrawn, desk-rejected, and workshop papers excluded
   → Script outputs source to stderr: "source: OpenReview"
   → If BibTeX returned: cross-check with DBLP (see DBLP cross-check below)
   → Tag: "via ICLR proceedings ✓ (DBLP cross-checked)" or
     "via ICLR proceedings ✓"

1. DBLP (highest quality for other published papers)
   → dblp_search.sh "<title>" 5
   → Check top result: tokenize both titles (split whitespace, lowercase)
   → If token overlap > 90% (intersection/union): confirmed match
   → If multiple results > 90%: prefer matching year + first author
   → Check matched result's venue:
     • If venue is "CoRR" (arXiv-only): skip DBLP BibTeX, go to step 1b
     • Otherwise: dblp_bibtex.sh "<matched_title>" "<first_author_surname>" "<year>"
       → Tag: "via DBLP"

1b. arXiv (for arXiv-only papers — replaces DBLP's CoRR entries)
   → Extract arXiv ID from: user input, DBLP volume field (abs/XXXX.XXXXX),
     or S2 externalIds.ArXiv
   → arxiv_bibtex.sh "<arxiv_id>"
   → Tag: "via arXiv"
   → Also reachable directly if user input is an arXiv ID and no published
     version exists in DBLP

2. CrossRef (DOI-based)
   → If DOI known: doi2bibtex.sh "<doi>"
   → If DOI unknown: crossref_search.sh "<title>" 3 → extract DOI → doi2bibtex.sh
   → Tag: "via CrossRef"

3. S2 (last resort, less reliable)
   → s2_match.sh "<title>"
   → If S2 result has externalIds.ArXiv and no published venue:
     → arxiv_bibtex.sh "<arxiv_id>" → Tag: "via arXiv"
   → Otherwise: construct BibTeX from S2 metadata
   → Tag: "via S2 — verify manually"
   → ⚠️ S2 metadata may have venue name inconsistencies or missing page numbers

4. All fail
   → Report: "Citation source not verified for: <title>. Not safe to cite."
   → Do NOT generate from model knowledge
```

### DBLP cross-check (applies to both CVF and NeurIPS golden sources)

**Why DBLP**: DBLP metadata is human-curated — we trust its content accuracy.
CVF/NeurIPS proceedings have better formatting (venue names, booktitle style),
but DBLP catches errors the proceedings sites may have (typos, wrong metadata).
Use the golden source BibTeX for FORMAT, DBLP for CONTENT verification.

When CVF (step 0a), NeurIPS (step 0b), or ICLR (step 0c) BibTeX is obtained, run
`dblp_search.sh "<title>" 3` in parallel to cross-check.

**Required checks** (must match — mismatch indicates wrong paper):

1. **Title**: token overlap > 90% (Jaccard). Minor formatting differences OK.
2. **First author**: last name must match (case-insensitive). DBLP may use
   different name ordering or abbreviation — that's OK as long as surnames match.
3. **Year**: must match exactly.
4. **Venue**: both must indicate the same conference.
   - CVF: full booktitle contains "(CVPR)" / "(ICCV)" / "(WACV)"
   - NeurIPS: booktitle is "Advances in Neural Information Processing Systems";
     DBLP uses "NeurIPS" or "NIPS"
   - ICLR: booktitle is "The Nth International Conference on Learning
     Representations"; DBLP uses "ICLR"
   - Match by checking the conference abbreviation appears in both.

**Enrichment checks** (if DBLP has it but golden source doesn't, supplement):

5. **Pages**: if DBLP has page numbers and the golden source BibTeX doesn't,
   add them (especially for OpenReview BibTeX which lacks pages).
6. **Volume**: if missing in golden source, add from DBLP.
7. **DOI**: if DBLP has a DOI and golden source doesn't, add it.

**Cross-check outcomes:**
- Required checks all pass → use golden source BibTeX (with any enrichment),
  tag: "via CVF ✓ (DBLP cross-checked)" / "via NeurIPS proceedings ✓ (DBLP
  cross-checked)" / "via ICLR proceedings ✓ (DBLP cross-checked)" /
  "via OpenReview ✓ (DBLP cross-checked)"
- DBLP unavailable or no match found → use golden source BibTeX as-is
  (it's the publisher), tag without "(DBLP cross-checked)"
- Required check mismatch → warn user, present both BibTeX entries for
  manual review (likely indicates wrong paper match)

### DBLP matching strategy

```python
# Pseudocode for title matching
def token_overlap(title_a, title_b):
    tokens_a = set(title_a.lower().split())
    tokens_b = set(title_b.lower().split())
    intersection = tokens_a & tokens_b
    union = tokens_a | tokens_b
    return len(intersection) / len(union)

# Accept if overlap > 0.90
```

### Step 3: Quality evaluation

For each cited paper, attach quality info:
```bash
bash scripts/venue_info.sh "<venue>"
bash scripts/author_info.sh "<first_author_id>"
```

### Step 3.5: Verification gate (`superpowers:verification-before-completion`)

Before outputting any BibTeX, invoke `superpowers:verification-before-completion` to confirm:
- Every BibTeX entry has all required fields populated from an API response (author, title, year, venue/booktitle/journal)
- The `source_tag` is set (no untagged entries)
- No field was filled from model memory — every value traces to a CVF/NeurIPS/ICLR/OpenReview/DBLP/CrossRef/S2 API call
- If source is "via S2", the manual-verify warning is attached

If any check fails, loop back to Step 2 to retry the next source in the chain. If the entire chain is exhausted, report failure — do not fabricate.

### Step 4: Output format

For each citation:

```
📄 Title (Year) — Venue
Source: via DBLP ✓
Quality: CCF-A | Citations: 1234 | h-index: 45

@inproceedings{He2016DeepRL,
  author    = {Kaiming He and ...},
  title     = {Deep Residual Learning for Image Recognition},
  booktitle = {CVPR},
  year      = {2016},
  ...
}
```

### Step 5: Save citation

Save BibTeX to `.research-workspace/sessions/{slug}/cite/{paper_id}.bib`

Update cite log at `.research-workspace/sessions/{slug}/cite/cite-log.json`:
```json
{
  "entries": [
    {
      "paper_id": "...",
      "title": "...",
      "source_tag": "via DBLP",
      "bibtex_key": "He2016DeepRL",
      "timestamp": "..."
    }
  ]
}
```

### Step 5.5: Checkpoint

Write checkpoint to `checkpoints/cite_{paper_id}_{timestamp}.json` with status `completed`, referencing the `.bib` file as the primary artifact. Include: paper_id, source_tag, bibtex_key.

### Step 6: Batch citation mode

When citing multiple papers (e.g., from survey results):
- Process all through the chain
- Group results by source tag
- Report any failures prominently at the end
- Output combined .bib file
