# Contributing Guidelines

Lessons learned from real bugs found during development. Follow these to avoid repeating past mistakes.

---

## Part 1: Implementation Checklist

### curl

- **Always use `-sL`**, never bare `-s`. The `-L` flag follows redirects and costs nothing. Without it, a 301/302 produces empty output that silently breaks downstream parsing. (Learned from: alphaxiv.org redirects to www.alphaxiv.org, causing all curl calls to return blank.)
- **Always capture HTTP status code** via `-w "\n%{http_code}"` for API calls. Parse the code and handle 429 (rate limit), 404 (not found), and other non-200 cases explicitly. Never assume 200. (Learned from: crossref_search.sh, dblp_search.sh, dblp_bibtex.sh, hf_daily_papers.sh, doi2bibtex.sh all lacked HTTP status capture, making rate limits and server errors invisible.)
- **Never discard stderr unconditionally** with `2>/dev/null` on the entire script. Use it only on the curl call itself, and preserve error messages from your own code on stderr.
- **Never detect errors by grepping response body.** `grep "404"` in a BibTeX response can false-positive if the content contains "404". `[[ "$RESPONSE" == "<!DOCTYPE"* ]]` is fragile. Always use `-w "\n%{http_code}"` to get the actual HTTP code. (Learned from: dblp_bibtex.sh used `grep "404"`, doi2bibtex.sh used DOCTYPE detection.)

**Reference pattern** (used by all S2 scripts):
```bash
RESPONSE=$(curl -sL -w "\n%{http_code}" \
    "https://api.example.com/endpoint" \
    --max-time 30 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200) # process $BODY ;;
    404) echo '{"error": "Not found"}' >&2; exit 1 ;;
    429) echo '{"error": "Rate limited"}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
```

### jq field mapping

- **Verify API response structure by actually calling the API**, not by guessing from docs or memory. Docs can be outdated; real responses are ground truth. (Learned from: S2 snippet API nests paper info under `.paper` object — `.paperId` was wrong, `.paper.corpusId` was correct. Also, authors were plain strings, not `{name}` objects.)
- **Test jq expressions on real data before committing.** Pipe a real API response through your jq filter and inspect every field. Null fields, empty strings, missing keys — all must be caught here, not in production.
- **jq `//` (alternative operator) does NOT catch empty strings.** `"" // "N/A"` evaluates to `""`, not `"N/A"`. If you need to replace empty strings, use `(if . == "" or . == null then "N/A" else . end)`. (Learned from: S2 API returns `""` for venue/journal on preprints; 7 S2 scripts output `"venue": ""` instead of `"venue": "N/A"` due to `//` not catching empty strings.)

**Vulnerable patterns and fixes:**
```bash
# BAD — empty string passes through
(.venue // "N/A")

# BAD — chained // still doesn't catch ""
(.venue // .journal // "N/A")

# GOOD — explicit empty-string check
(.venue | if . == "" or . == null then null else . end) as $v |
(.journal | if . == "" or . == null then null else . end) as $j |
($v // $j // "N/A")

# GOOD — single field
(if .venue == "" or .venue == null then "N/A" else .venue end)
```

### Empty / no-results handling

- **Empty stdout with exit 0 is a bug.** If a query returns no results, the script must either: (a) output an informative message to stderr, or (b) exit with a non-zero code. Silent empty output causes downstream confusion. (Learned from: ccf_lookup.sh, if_lookup.sh, dblp_search.sh all silently returned nothing.)
- **Pattern to avoid:** `sqlite3 ... | jq '.[]?'` — when the result is `[]`, jq produces no output and exits 0. Fix: capture the result first, check if empty/`[]`, then either print a stderr message or process normally.
- **Pattern to avoid:** `jq '.items[]?' || echo '[]'` — jq exits 0 even when producing no output, so `||` never triggers.
- **Non-JSON error responses break jq silently.** If an API returns a 500 HTML error page, jq fails with a parse error. With `set -e`, this terminates the script with a cryptic message. Always validate HTTP status code BEFORE piping to jq. (Learned from: crossref_search.sh, dblp_search.sh, hf_daily_papers.sh all piped raw response to jq without checking if it was valid JSON.)

### Data integrity in jq transforms

- **Check array length BEFORE slicing.** If you want "first 3 authors + et al.", check `length > 3` on the full array, then slice. Do not slice first and check length after — you'll never exceed the threshold. (Learned from: crossref et al. logic.)
- **Handle single-element vs array ambiguity.** Some APIs (DBLP) return a single object when there's one author, and an array when there are multiple. Always check `type == "array"` before iterating.

### Defensive defaults

- Add `-L` to all curl calls (redirect safety).
- Add `--max-time` to all curl calls (timeout safety).
- Use `set -e` at script top (fail-fast on errors).
- Source `init.sh` for rate limiting, API keys, and shared config. Every script that makes HTTP calls should source init.sh. (Learned from: crossref_search.sh, doi2bibtex.sh, hf_daily_papers.sh didn't source init.sh, missing rate limiting and shared config.)

### Consistency standards

- **All scripts must follow the same error reporting pattern.** Error messages go to stderr as JSON: `echo '{"error": "description"}' >&2`. Informational metadata (total results, etc.) also to stderr.
- **Exit codes**: 0 = success with output, 1 = error. Never exit 0 with no stdout and no stderr.

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
- **Add content assertions**: verify title/venue/author contains expected words for the test fixture. (Learned from: tests that only check `has("field")` or `!= null` pass even with wrong data.)

**Error path:**
- Call with no arguments — should exit non-zero with usage message on stderr.
- Call with invalid input (nonexistent ID, garbage query) — should either return informative error or empty-with-message, never silent empty.

**Edge cases:**
- Query with zero results — must not produce silent empty output.
- Response with missing optional fields (no DOI, no abstract, no PDF URL).
- Author count edge cases: 0 authors, 1 author, exactly 3 authors, 4+ authors.
- Empty-string fields (venue, journal, abstract) — must not output `""` where `"N/A"` is expected.

### Test coverage requirements

Every script must have a test. Current gaps that must be filled:

| Script | Status | Required |
|--------|--------|----------|
| s2_recommend.sh | **NO TEST** | Create test_s2_recommend.sh |
| author_info.sh | **NO TEST** | Create test_author_info.sh |
| All scripts | Missing no-args test | Add explicit no-args exit-code check |
| All scripts | Missing invalid-input test | Add garbage-input test |
| All scripts | Missing zero-results test | Add nonsense-query test |

### How to verify (execution, not assumption)

1. **Actually run the script**: `bash scripts/foo.sh "real_input" 2>&1`
2. **Inspect every field**: pipe output to `jq .` and read each value.
3. **If output is empty or suspicious**: immediately investigate with `curl -sI <url>` to check HTTP status and headers. Cross-validate with WebFetch or a browser. Empty is NEVER "probably fine".
4. **Test the test**: introduce a deliberate bug in the script, run the test, confirm the test catches it. If the test still passes with a bug, the test is worthless.
5. **Verify empty-string handling**: For scripts outputting venue/journal/abstract, check that preprints (papers without venue) output `"N/A"` not `""`.

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
| jq `//` on empty strings | `(.venue // "N/A")` outputs `""` | Use `if . == "" or . == null then "N/A" else . end` |
| grep "404" in body | BibTeX content contains "404" → false positive | Use `-w "\n%{http_code}"` to check HTTP status, not body content |
| Non-JSON error pages | 500 HTML response piped to jq → cryptic error | Check HTTP status BEFORE piping to jq |
| `set -e` + jq `-e` in condition | `jq -e '.message == null'` exits non-zero → script terminates | Use explicit `if` blocks instead of relying on jq exit codes in conditions |

---

## Part 3: Pre-Push Verification Protocol

Before pushing any changes, complete this checklist in order:

### Step 1: Static analysis
- [ ] All curl calls use `-sL` (not bare `-s`)
- [ ] All curl calls capture HTTP status code with `-w "\n%{http_code}"`
- [ ] All curl calls have `--max-time`
- [ ] All scripts have `set -e`
- [ ] All scripts with HTTP calls source `init.sh`
- [ ] No `jq ... //` on fields that can be empty strings (venue, journal, abstract, summary)
- [ ] No `grep` on response body for error detection (use HTTP status codes)
- [ ] No `2>/dev/null` on jq or full pipelines (only on curl calls)

### Step 2: Execute every script
For EACH script, run with real inputs and inspect output:
```bash
# Happy path — verify all fields are populated and correct
bash scripts/foo.sh "valid_input" 2>&1 | jq .

# Error path — verify exit code and stderr message
bash scripts/foo.sh 2>&1; echo "exit: $?"
bash scripts/foo.sh "nonexistent_garbage_id_12345" 2>&1; echo "exit: $?"

# Edge case — verify empty-string fields handled
# (use a preprint paper ID to test venue="" handling)
```

### Step 3: Run full test suite
```bash
bash tests/run_all_tests.sh
```

### Step 4: Cross-validate suspicious output
If any output is empty, blank, or has unexpected values:
1. `curl -sI <url>` to check HTTP status and headers
2. `curl -sL <url> | head -20` to see raw response
3. WebFetch the URL to cross-validate
4. NEVER dismiss empty output as "probably fine"

### Step 5: Verify test quality
For each modified script, temporarily break it and confirm its test catches the bug:
```bash
# Example: change "N/A" to "BROKEN" in script, run test, expect FAIL
# If test still passes → test is worthless → fix the test first
```
