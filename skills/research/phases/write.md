# Write Phase

Full conference paper section writing with verified citations.

## Trigger

Called via `/research write <section>` where section is: abstract, introduction, related-work, method, experiments, conclusion, discussion, or any custom section name.

## Output Format Detection

Auto-detect based on workspace context:

1. **LaTeX workspace detected**: check current working directory and parents for `*.tex` or `*.bib` files. If found → output LaTeX directly, no confirmation needed.
2. **Otherwise**: ask user to choose — LaTeX, Markdown, or Notion (via Notion MCP).

## Context Sources

Read the user's own content from:
- `.tex` files from overleaf git clone (if present)
- Prior discover/read/cite results from `.research-workspace/`
- Notion pages (if user specifies, via Notion MCP)
- User's direct instructions and notes

## Workflow

### Step 1: Gather context

1. Check for `.tex` files in workspace — read existing draft sections
2. Load relevant read analyses from `.research-workspace/sessions/*/read/`
3. Load cite-log for already-verified citations
4. Understand the paper's positioning from discover results

### Step 1.5: Invoke Skill Router (skill-router)

Invoke the skill router with:
- Input: paper metadata from the research brief + read analyses
- Phase type: `write`
- Router returns primary domain skills for technical accuracy review

Also load the research brief from discuss phase if available:
`.research-workspace/sessions/{slug}/discuss/brief.json`

**Context source priority** (updated):
1. Research brief from discuss phase — primary framing source
2. Read analyses from workspace — detailed technical content
3. Existing `.tex` files — current draft state
4. Cite-log — verified citations
5. User's direct instructions

### Step 2: Invoke ml-paper-writing skill

Use the `ml-paper-writing` skill (from Orchestra-Research AI-Research-SKILLs plugin) for:
- Paper structure conventions for the target venue
- Section-specific writing guidelines
- Common patterns for ML/AI papers

### Step 3: Write the section

Generate the requested section following academic conventions:
- Clear, concise prose
- Proper citation format (`\cite{key}` for LaTeX)
- Logical flow and argumentation
- Quantitative claims backed by data from read analyses

### Step 4: Verify all citations

**Every `\cite{key}` in the output must be verified through the cite phase.**

For each citation reference in the written text:
1. Check cite-log — if already verified, use existing BibTeX
2. If not verified — run cite phase for that paper
3. If cite phase fails — flag the citation and ask user

No unverified citations in the final output.

### Step 5: Style review

Invoke the `humanizer` skill to review the written text for:
- AI writing patterns to remove
- Natural academic voice
- Clarity and conciseness

### Step 5.5: Triple Review Gate (abstract + introduction only)

If the section being written is `abstract` or `introduction`, auto-trigger three review perspectives after the initial draft:

**Reviewer Perspective (Technical Rigor):**
- Is the motivation backed by a concrete failure mode, not an abstract gap?
- Are contributions clearly distinguished from prior work?
- Do claims align with what the experiments can demonstrate?
- Output: 2-3 specific revision suggestions pointing to concrete sentences.

**AC/SAC Perspective (Novelty & Significance):**
- Can the contribution be summarized in one sentence that a non-expert understands?
- Is this incremental or substantial? What's the delta over closest prior work?
- Is there concurrent work risk? (Check recent arXiv for similar submissions)
- Output: 2-3 specific revision suggestions pointing to concrete sentences.

**Senior Researcher Perspective (Impact & Elegance):**
- "If this research succeeds perfectly, who does something differently tomorrow?"
- Is the problem framing revealing a deeper insight, or just stating a gap?
- Is this the simplest, most elegant formulation of the contribution?
- Output: 2-3 specific revision suggestions pointing to concrete sentences.

**Cross-model adversarial review** (framing gate):
After the three perspectives above, invoke `mcp__codex__codex` per Cross-Model Collaboration #9 in SKILL.md. Send:
- The draft abstract or introduction text
- The research brief from discuss phase (if available)

Ask: "As an AC at {target venue}: (1) Does the motivation hold up? (2) Is the contribution clearly distinguished from prior work? (3) What would make you desk-reject this?"

Present cross-model concerns labeled `[Cross-model review]` alongside the three Claude perspectives. If Codex MCP is unavailable, skip and proceed.

Present all suggestions (Claude's three perspectives + cross-model) to user. User decides which to adopt. Optional re-run after revision.

### Step 5.6: Related Work Coverage & Fairness Check (related-work only)

If the section being written is `related-work`, auto-trigger a coverage and fairness review:

**Claude's check**:
- Cross-reference all papers cited in related-work against discover results and read analyses — are key papers from the landscape missing?
- For each cited paper: is the characterization accurate based on read analysis? Is the comparison fair?
- Is our contribution's positioning honest and precise (not overselling delta over prior work)?

**Codex coverage check** (adversarial mode):
Invoke `mcp__codex__codex` per Cross-Model Collaboration #10 in SKILL.md. Send the draft related-work section + discover results + read analyses. Ask:
- "What important related work is missing?"
- "Is any prior work mischaracterized or unfairly compared?"
- "Is the positioning of the contribution honest and precise?"

If Codex MCP is unavailable, proceed with Claude-only coverage check (log warning).

Present both checks to the user (or Claude-only if Codex unavailable). Missing references flagged by either model should be investigated (quick-read + cite if confirmed relevant).

### Step 5.65: Consistency Check (method, experiments, conclusion)

If the section being written is `method`, `experiments`, `conclusion`, or `discussion`, run a lightweight structural cross-reference scan against existing draft sections:

- Introduction lists N contributions → does experiments have a corresponding table/figure for each?
- Method assumes specific input format → does the dataset actually provide that format?
- Abstract claims "state-of-the-art" → do results show superiority over ALL listed baselines?
- Conclusion doesn't overclaim beyond what experiments demonstrate
- Method's assumptions match experiment setup (e.g., "RGB-IR pair" input → dataset provides IR)

Flag inconsistencies for user to resolve. Do not auto-fix — the user decides which side to change.

### Step 5.7: Verification gate (`superpowers:verification-before-completion`)

Before presenting the section to the user, invoke `superpowers:verification-before-completion` to confirm:
- Every `\cite{key}` in the text has a corresponding verified BibTeX entry (cross-check against cite-log)
- No quantitative claim (numbers, percentages, rankings) lacks a traceable source (paper ID or API response)
- The humanizer pass was actually applied (not skipped)
- If abstract/introduction: the triple review gate was completed; cross-model framing gate was completed OR skipped due to Codex unavailability (with warning logged)
- If related-work: the coverage & fairness check was completed (Claude-only is acceptable if Codex is unavailable, with warning logged)
- If method/experiments/conclusion/discussion: the consistency check was completed

Only proceed to presentation after all checks pass. If citation verification fails for >30% of references, trigger PUA escalation per Iron Rule.

### Step 6: Present to user

Show the written section with:
- The full text (LaTeX or Markdown)
- List of citations used (with source tags)
- Any flagged issues (unverified citations, uncertain claims)
- Suggested BibTeX entries to add to the `.bib` file

Ask user to review before finalizing.

### Step 7: Output

If LaTeX workspace:
- Show the LaTeX code for the user to paste into their `.tex` file
- Show new BibTeX entries to append to `.bib`

If Markdown:
- Show the formatted markdown
- Show references list at the bottom

If Notion:
- Use Notion MCP to create/update a page with the section content

**Checkpoint**: After Step 7 completes, write checkpoint to `checkpoints/write_{section}_{timestamp}.json` capturing: section name, output format, citations used (with source tags), whether triple review / cross-model review / consistency check were applied, and any flagged issues.

## Supported Sections

| Section | Key elements |
| --- | --- |
| Abstract | Problem, method, key results, significance |
| Introduction | Motivation, gap, contribution, paper organization |
| Related Work | Organized by sub-topic, compare & contrast, position own work |
| Method | Architecture, loss functions, training procedure, key design choices |
| Experiments | Setup, baselines, metrics, main results, ablations |
| Conclusion | Summary, limitations, future work |
| Discussion | Broader implications, failure analysis, ethical considerations |

## Language

All output in English. For uncommon vocabulary (GRE-level), add Chinese translation in parentheses.
