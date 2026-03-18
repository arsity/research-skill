# Contributing Guidelines

Lessons learned from real bugs found during development. Follow these to avoid repeating past mistakes.

---

## Part 1: Implementation Checklist

### curl

- **Always use `-sL`**, never bare `-s`. The `-L` flag follows redirects and costs nothing. Without it, a 301/302 produces empty output that silently breaks downstream parsing. (Learned from: alphaxiv.org redirects to www.alphaxiv.org, causing all curl calls to return blank.)
- **Always capture HTTP status code** via `-w "\n%{http_code}"` for API calls. Parse the code and handle 429 (rate limit), 404 (not found), and other non-200 cases explicitly. Never assume 200.
- **Never discard stderr unconditionally** with `2>/dev/null` on the entire script. Use it only on the curl call itself, and preserve error messages from your own code on stderr.

### jq field mapping

- **Verify API response structure by actually calling the API**, not by guessing from docs or memory. Docs can be outdated; real responses are ground truth. (Learned from: S2 snippet API nests paper info under `.paper` object — `.paperId` was wrong, `.paper.corpusId` was correct. Also, authors were plain strings, not `{name}` objects.)
- **Test jq expressions on real data before committing.** Pipe a real API response through your jq filter and inspect every field. Null fields, empty strings, missing keys — all must be caught here, not in production.
- **jq `//` (alternative operator) does NOT catch empty strings.** `"" // "N/A"` evaluates to `""`, not `"N/A"`. If you need to replace empty strings, use `(if . == "" or . == null then "N/A" else . end)`.

### Empty / no-results handling

- **Empty stdout with exit 0 is a bug.** If a query returns no results, the script must either: (a) output an informative message to stderr, or (b) exit with a non-zero code. Silent empty output causes downstream confusion. (Learned from: ccf_lookup.sh, if_lookup.sh, dblp_search.sh all silently returned nothing.)
- **Pattern to avoid:** `sqlite3 ... | jq '.[]?'` — when the result is `[]`, jq produces no output and exits 0. Fix: capture the result first, check if empty/`[]`, then either print a stderr message or process normally.
- **Pattern to avoid:** `jq '.items[]?' || echo '[]'` — jq exits 0 even when producing no output, so `||` never triggers.

### Data integrity in jq transforms

- **Check array length BEFORE slicing.** If you want "first 3 authors + et al.", check `length > 3` on the full array, then slice. Do not slice first and check length after — you'll never exceed the threshold. (Learned from: crossref et al. logic.)
- **Handle single-element vs array ambiguity.** Some APIs (DBLP) return a single object when there's one author, and an array when there are multiple. Always check `type == "array"` before iterating.

### Defensive defaults

- Add `-L` to all curl calls (redirect safety).
- Add `--max-time` to all curl calls (timeout safety).
- Use `set -e` at script top (fail-fast on errors).
- Source `init.sh` for rate limiting, API keys, and shared config.

---

## Part 2: Testing & Debugging Checklist

### Before writing tests

- **Verify test fixtures against reality.** If your test uses a paper ID labeled "ResNet", actually call the API with that ID and confirm the returned title is "Deep Residual Learning for Image Recognition". (Learned from: test_s2_batch.sh and test_s2_network.sh used ID `649def...` which is actually "Construction of the Literature Graph", not ResNet.)
- **Verify test keywords against actual content.** If your test checks for keywords "mixtral|moe", fetch the actual content at that ID and confirm those words appear — not by coincidence (e.g., "expertise" matching "expert"), but because the content is genuinely about that topic. (Learned from: test_alphaxiv.sh checked for Mixtral keywords on paper 2401.10891, which is actually Depth Anything.)

### What to test for each script

**Happy path:**
- Call with valid input, verify output is non-empty.
- Check that ALL output fields are the expected type (string, number, array, null).
- Verify field VALUES are plausible (not all null, not all "N/A").

**Error path:**
- Call with no arguments — should exit non-zero with usage message on stderr.
- Call with invalid input (nonexistent ID, garbage query) — should either return informative error or empty-with-message, never silent empty.

**Edge cases:**
- Query with zero results — must not produce silent empty output.
- Response with missing optional fields (no DOI, no abstract, no PDF URL).
- Author count edge cases: 0 authors, 1 author, exactly 3 authors, 4+ authors.

### How to verify (execution, not assumption)

1. **Actually run the script**: `bash scripts/foo.sh "real_input" 2>&1`
2. **Inspect every field**: pipe output to `jq .` and read each value.
3. **If output is empty or suspicious**: immediately investigate with `curl -sI <url>` to check HTTP status and headers. Cross-validate with WebFetch or a browser. Empty is NEVER "probably fine".
4. **Test the test**: introduce a deliberate bug in the script, run the test, confirm the test catches it. If the test still passes with a bug, the test is worthless.

### Regression testing after changes

After modifying any script:
1. Run that script's test file directly: `bash tests/test_foo.sh`
2. Run the full suite: `bash tests/run_all_tests.sh`
3. Manually run the modified script with a real query and inspect the output.

### Common traps

| Trap | Example | How to catch |
|------|---------|-------------|
| Accidental keyword match | grep "expert" matches "expertise" | Use `grep -w` for whole-word match, or use more specific multi-word patterns |
| Test passes by coincidence | Wrong paper ID but test only checks field existence | Add content assertions (verify title contains expected words) |
| jq exits 0 with no output | `.data[]?` on empty array | Check output length or use `jq -e` |
| curl redirect → empty body | 301 without `-L` | Always use `-sL`; in tests, check content length > threshold |
| API response structure change | Field renamed or nested differently | Pin a known ID/query and assert specific field values, not just existence |
