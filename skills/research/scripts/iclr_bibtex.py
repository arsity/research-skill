#!/usr/bin/env python3
"""ICLR BibTeX fetch — golden standard for ICLR papers.

Usage: python3 scripts/iclr_bibtex.py "paper title" "year"

Dual-API strategy:
  ICLR proceedings live entirely on OpenReview — no separate proceedings site.
  - ICLR 2024+: OpenReview API v2 (api2.openreview.net)
  - ICLR 2018-2023: OpenReview API v1 (api.openreview.net)
  Papers were migrated from v1 to v2 starting in 2024. Older years remain
  on v1 only. Both APIs provide _bibtex and venueid fields.

Acceptance filtering (CRITICAL for citation safety):
  Only papers with venueid == "ICLR.cc/{year}/Conference" are accepted.
  Rejected, withdrawn, desk-rejected, and workshop papers all have different
  venueid patterns and MUST be excluded:
    - ICLR.cc/YYYY/Conference/Rejected_Submission  (rejected or desk-rejected)
    - ICLR.cc/YYYY/Conference/Withdrawn_Submission  (withdrawn)
    - ICLR.cc/YYYY/Workshop/*                       (workshop papers)
    - ICLR.cc/YYYY/Workshop_Proposals               (workshop proposals)

Source identification:
  Outputs {"info": "source: OpenReview"} to stderr.

Outputs BibTeX to stdout. Errors as JSON to stderr. Exit 0 on success, 1 on error.
"""

import json
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from typing import Optional

OPENREVIEW_V1_API = "https://api.openreview.net"
OPENREVIEW_V2_API = "https://api2.openreview.net"
# ICLR 2024+ uses v2 API; 2018-2023 uses v1 API
V2_MIN_YEAR = 2024
# v1 API has venueid from 2021+; 2018-2020 lack acceptance status.
# ICLR 2018-2020 should use DBLP (which only indexes accepted papers).
MIN_YEAR = 2021
REQUEST_TIMEOUT = 15
# OpenReview rejects short/bot-like User-Agents with 403
OPENREVIEW_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)


def die(msg):
    # type: (str) -> None
    print(json.dumps({"error": msg}), file=sys.stderr)
    sys.exit(1)


def info(msg):
    # type: (str) -> None
    print(json.dumps({"info": msg}), file=sys.stderr)


def ascii_fold(s):
    # type: (str) -> str
    """NFKD Unicode decomposition -> ASCII."""
    special = {
        "\u00df": "ss",   # ß
        "\u00f8": "o",    # ø
        "\u00d8": "O",    # Ø
        "\u00e6": "ae",   # æ
        "\u00c6": "AE",   # Æ
        "\u0153": "oe",   # œ
        "\u0152": "OE",   # Œ
        "\u00f0": "d",    # ð
        "\u00fe": "th",   # þ
        "\u0142": "l",    # ł
        "\u0141": "L",    # Ł
    }
    for char, repl in special.items():
        s = s.replace(char, repl)
    return unicodedata.normalize("NFKD", s).encode("ascii", errors="ignore").decode("ascii")


def normalize_title(title):
    # type: (str) -> str
    """Normalize for comparison: strip LaTeX, fold Unicode, lowercase, alphanumeric only."""
    s = title
    s = re.sub(r"\\textemdash", " ", s)
    s = re.sub(r"\\textendash", " ", s)
    s = s.replace("\u2014", " ").replace("\u2013", " ")
    s = s.replace("\\ss", "ss")
    s = s.replace("\\o", "o")
    s = s.replace("\\O", "O")
    s = s.replace("\\ae", "ae")
    s = s.replace("\\AE", "AE")
    s = s.replace("\\oe", "oe")
    s = s.replace("\\OE", "OE")
    s = s.replace("\\l", "l")
    s = s.replace("\\L", "L")
    s = re.sub(r"\\['\"`^~=.Huvcdbtr]", "", s)
    s = ascii_fold(s)
    return re.sub(r"[^a-z0-9]", "", s.lower())


def _normalize_for_tokens(s):
    # type: (str) -> str
    """Normalize Unicode punctuation to ASCII for consistent tokenization."""
    s = s.replace("\u2018", "'").replace("\u2019", "'")
    s = s.replace("\u201c", '"').replace("\u201d", '"')
    s = s.replace("\u2014", "-").replace("\u2013", "-")
    return s


def token_overlap(a, b):
    # type: (str, str) -> float
    """Jaccard token overlap between two titles."""
    ta = set(_normalize_for_tokens(a).lower().split())
    tb = set(_normalize_for_tokens(b).lower().split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def extract_bibtex_title(bibtex):
    # type: (str) -> Optional[str]
    """Extract title field from BibTeX using manual brace counting."""
    m = re.search(r"(?<![a-zA-Z])title\s*=\s*\{", bibtex)
    if not m:
        return None
    start = m.end()
    depth = 1
    i = start
    while i < len(bibtex) and depth > 0:
        if bibtex[i] == "{":
            depth += 1
        elif bibtex[i] == "}":
            depth -= 1
        i += 1
    if depth != 0:
        return None
    title = bibtex[start:i - 1]
    title = re.sub(r"\{([^{}]*)\}", r"\1", title)
    return title.strip()


def fetch_url(url, accept="text/html", ua=None):
    # type: (str, str, Optional[str]) -> Optional[str]
    """Fetch URL, return body on 2xx, None otherwise."""
    req = urllib.request.Request(url, headers={
        "User-Agent": ua or OPENREVIEW_UA,
        "Accept": accept,
    })
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        if e.code == 429:
            import time
            time.sleep(2)
            try:
                with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp2:
                    return resp2.read().decode("utf-8", errors="replace")
            except Exception:
                pass
        if e.code not in (404, 410, 429):
            info("HTTP {} for {}".format(e.code, url))
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        info("Connection error for {}: {}".format(url, e))
    return None


def _get_note_title(note):
    # type: (dict) -> str
    """Extract title string from an OpenReview note (handles dict or str)."""
    t = note.get("content", {}).get("title", {})
    if isinstance(t, dict):
        return t.get("value", "")
    return str(t) if t else ""


def _get_note_venueid(note):
    # type: (dict) -> str
    """Extract venueid from an OpenReview note (handles dict or str)."""
    vid = note.get("content", {}).get("venueid", {})
    if isinstance(vid, dict):
        return vid.get("value", "")
    return str(vid) if vid else ""


def _get_note_bibtex(note):
    # type: (dict) -> str
    """Extract BibTeX from an OpenReview note (handles dict or str)."""
    bib = note.get("content", {}).get("_bibtex", {})
    if isinstance(bib, dict):
        return bib.get("value", "")
    return str(bib) if bib else ""


def is_accepted_iclr(venueid, year):
    # type: (str, int) -> bool
    """Check if a venueid indicates an accepted ICLR main conference paper.

    Accepted papers have venueid == "ICLR.cc/{year}/Conference" EXACTLY.
    This naturally excludes rejected, withdrawn, and workshop papers,
    all of which have suffixes on the venueid.
    """
    expected = "ICLR.cc/{}/Conference".format(year)
    return venueid == expected


def _sanitize_query(title):
    # type: (str) -> str
    """Sanitize title for OpenReview search query.

    Strip colons, parentheses, and other punctuation that degrade
    search quality, keeping only alphanumeric, spaces, and hyphens.
    """
    s = title.replace("\u2014", " ").replace("\u2013", " ")
    # Keep Unicode letters (\w includes [a-zA-Z0-9_] + Unicode letters),
    # spaces, hyphens, and plus signs. Strip colons, parens, etc.
    # Preserves accented chars (é, ü) so "Déjà Vu" doesn't become "D j Vu".
    s = re.sub(r"[^\w\s\-+]", " ", s)
    s = s.replace("_", " ")  # remove underscores that \w lets through
    return re.sub(r"\s+", " ", s).strip()


def _get_note_venue(note):
    # type: (dict) -> str
    """Extract venue display string from an OpenReview note (handles dict or str)."""
    v = note.get("content", {}).get("venue", {})
    if isinstance(v, dict):
        return v.get("value", "")
    return str(v) if v else ""


def _filter_candidates(notes, title, year):
    # type: (list, str, int) -> tuple
    """Filter OpenReview notes to accepted ICLR papers matching title and year.

    Returns (candidate_notes, diagnostics) where candidate_notes is a list of
    (note, overlap) tuples sorted by overlap descending, and diagnostics is a
    dict with rejection counts for error reporting.

    Uses THREE acceptance checks for safety:
    1. venueid == "ICLR.cc/{year}/Conference" exact match (primary)
    2. venue string must match accepted allowlist: Poster/Oral/Spotlight (secondary)
    3. BibTeX type must be @inproceedings, not @misc (tertiary)
    The v1 API has data quality issues where some rejected papers have the
    correct venueid but venue="Submitted to ICLR YYYY".
    """
    candidates = []  # type: list  # [(note, overlap)]
    diag = {"rejected": 0, "withdrawn": 0, "workshop": 0}

    for note in notes:
        vid = _get_note_venueid(note)
        if not vid:
            continue

        # Skip DBLP-indexed entries
        if vid.startswith("dblp.org/"):
            continue

        # Must be ICLR
        if "ICLR" not in vid:
            continue

        # Track rejection types for diagnostics
        if "Rejected_Submission" in vid:
            diag["rejected"] += 1
            continue
        if "Withdrawn_Submission" in vid:
            diag["withdrawn"] += 1
            continue
        if "Workshop" in vid:
            diag["workshop"] += 1
            continue

        # CRITICAL: Check acceptance via exact venueid match
        if not is_accepted_iclr(vid, year):
            info("Skipping non-accepted venueid: {}".format(vid))
            continue

        # SECONDARY CHECK: Positive allowlist for accepted venue strings.
        # The v1 API has data quality issues where non-accepted papers can
        # have the correct venueid. Instead of blacklisting specific bad
        # strings, we require the venue to match known accepted patterns.
        # Accepted papers have venue like "ICLR YYYY Poster/Oral/Spotlight"
        # or "Tiny Papers @ ICLR YYYY".
        venue_str = _get_note_venue(note)
        venue_lower = venue_str.lower()
        is_accepted_venue = bool(
            # Standard acceptance types: "ICLR 2024 poster", "ICLR 2025 Oral"
            # Tiny Papers have separate venueid (ICLR.cc/YYYY/TinyPapers),
            # blocked by the exact venueid match above — not in scope here.
            re.search(r"iclr\s+\d{4}\s+(poster|oral|spotlight)", venue_lower)
        )
        if venue_str and not is_accepted_venue:
            info("Skipping paper with non-accepted venue string: '{}'".format(
                venue_str
            ))
            diag["rejected"] += 1
            continue
        # If venue is blank (missing data), also skip — cannot confirm acceptance
        if not venue_str:
            info("Skipping paper with blank venue despite accepted venueid")
            diag["rejected"] += 1
            continue

        nt = _get_note_title(note)
        if not nt:
            continue

        ov = token_overlap(title, nt)
        if ov >= 0.90:
            candidates.append((note, ov))

    candidates.sort(key=lambda x: x[1], reverse=True)
    return candidates, diag


def _extract_verified_bibtex(candidates, title):
    # type: (list, str) -> Optional[str]
    """From candidate notes, extract and title-verify BibTeX.

    Returns the first BibTeX that passes title verification, or None.
    """
    for note, _ in candidates:
        bibtex = _get_note_bibtex(note)
        bibtex = bibtex.strip()
        if not bibtex.startswith("@"):
            continue

        bib_title = extract_bibtex_title(bibtex)
        if not bib_title:
            continue
        if normalize_title(bib_title) != normalize_title(title):
            info("OpenReview title mismatch: requested '{}', got '{}'".format(
                title, bib_title
            ))
            continue

        # Fail closed: accepted ICLR papers use @inproceedings.
        # @misc indicates a non-published submission — do NOT return it.
        if bibtex.startswith("@misc"):
            info("Rejecting @misc BibTeX — accepted papers use @inproceedings")
            continue

        return bibtex

    return None


def search_openreview_v2(title, year):
    # type: (str, int) -> Optional[str]
    """Search OpenReview API v2 (ICLR 2024+) by title, return BibTeX if found."""
    sanitized = _sanitize_query(title)
    query = urllib.parse.quote_plus(sanitized)
    url = "{}/notes/search?query={}&source=forum&limit=10".format(
        OPENREVIEW_V2_API, query
    )

    resp = fetch_url(url, accept="application/json", ua=OPENREVIEW_UA)

    # Retry strategy for transient failures
    if resp is None:
        resp = fetch_url(url, accept="application/json", ua=OPENREVIEW_UA)
    if resp is None:
        folded = _sanitize_query(ascii_fold(title))
        query_f = urllib.parse.quote_plus(folded)
        url_f = "{}/notes/search?query={}&source=forum&limit=10".format(
            OPENREVIEW_V2_API, query_f
        )
        resp = fetch_url(url_f, accept="application/json", ua=OPENREVIEW_UA)
    if resp is None:
        folded = _sanitize_query(ascii_fold(title))
        words = [w for w in folded.split() if len(w) > 3]
        if words:
            query2 = urllib.parse.quote_plus(" ".join(words))
            url2 = "{}/notes/search?query={}&source=forum&limit=10".format(
                OPENREVIEW_V2_API, query2
            )
            resp = fetch_url(url2, accept="application/json", ua=OPENREVIEW_UA)
    if not resp:
        info("OpenReview v2 search request failed")
        return None

    try:
        data = json.loads(resp)
    except json.JSONDecodeError:
        info("OpenReview v2 returned invalid JSON")
        return None

    notes = data.get("notes", [])

    # Retry with simplified query if empty results
    if not notes:
        folded = _sanitize_query(ascii_fold(title))
        for retry_query in [folded, " ".join(w for w in folded.split() if len(w) > 4)]:
            if not retry_query.strip():
                continue
            rq = urllib.parse.quote_plus(retry_query)
            ru = "{}/notes/search?query={}&source=forum&limit=10".format(
                OPENREVIEW_V2_API, rq
            )
            rr = fetch_url(ru, accept="application/json", ua=OPENREVIEW_UA)
            if rr:
                try:
                    rd = json.loads(rr)
                    rn = rd.get("notes", [])
                    if rn:
                        notes = rn
                        break
                except json.JSONDecodeError:
                    pass

    if not notes:
        info("No results from OpenReview v2 search")
        return None

    candidates, diag = _filter_candidates(notes, title, year)

    if not candidates:
        diag_parts = []
        for k, v in diag.items():
            if v:
                diag_parts.append("{} {}".format(v, k))
        diag_str = " (filtered: {})".format(", ".join(diag_parts)) if diag_parts else ""
        best_ov = max((token_overlap(title, _get_note_title(n)) for n in notes), default=0.0)
        info("No accepted ICLR paper on OpenReview v2 for year {} (best overlap: {:.2f}){}".format(
            year, best_ov, diag_str
        ))
        return None

    bibtex = _extract_verified_bibtex(candidates, title)
    if bibtex:
        info("source: OpenReview")
        return bibtex

    info("OpenReview v2: all {} candidate(s) failed title verification".format(
        len(candidates)
    ))
    return None


def search_openreview_v1(title, year):
    # type: (str, int) -> Optional[str]
    """Search OpenReview API v1 (ICLR 2018-2023) by title, return BibTeX if found.

    v1 API uses:
    - /notes/search?query=&group=ICLR.cc/{year}/Conference for search
    - Content fields are direct strings (not {"value": "..."} dicts)
    - Same _bibtex and venueid fields as v2
    """
    sanitized = _sanitize_query(title)
    query = urllib.parse.quote_plus(sanitized)
    group = "ICLR.cc/{}/Conference".format(year)
    url = "{}/notes/search?query={}&group={}&limit=10".format(
        OPENREVIEW_V1_API, query, group
    )

    resp = fetch_url(url, accept="application/json", ua=OPENREVIEW_UA)

    # Retry with ASCII-folded query
    if resp is None:
        folded = _sanitize_query(ascii_fold(title))
        query_f = urllib.parse.quote_plus(folded)
        url_f = "{}/notes/search?query={}&group={}&limit=10".format(
            OPENREVIEW_V1_API, query_f, group
        )
        resp = fetch_url(url_f, accept="application/json", ua=OPENREVIEW_UA)
    # Retry with content words only
    if resp is None:
        folded = _sanitize_query(ascii_fold(title))
        words = [w for w in folded.split() if len(w) > 3]
        if words:
            query2 = urllib.parse.quote_plus(" ".join(words))
            url2 = "{}/notes/search?query={}&group={}&limit=10".format(
                OPENREVIEW_V1_API, query2, group
            )
            resp = fetch_url(url2, accept="application/json", ua=OPENREVIEW_UA)
    if not resp:
        info("OpenReview v1 search request failed")
        return None

    try:
        data = json.loads(resp)
    except json.JSONDecodeError:
        info("OpenReview v1 returned invalid JSON")
        return None

    notes = data.get("notes", [])

    # Filter out non-paper results (reviews, comments, etc.)
    # Paper notes have venueid set; reviews/comments don't
    paper_notes = [n for n in notes if _get_note_venueid(n)]

    if not paper_notes:
        # Retry with simplified query
        folded = _sanitize_query(ascii_fold(title))
        for retry_query in [folded, " ".join(w for w in folded.split() if len(w) > 4)]:
            if not retry_query.strip():
                continue
            rq = urllib.parse.quote_plus(retry_query)
            ru = "{}/notes/search?query={}&group={}&limit=10".format(
                OPENREVIEW_V1_API, rq, group
            )
            rr = fetch_url(ru, accept="application/json", ua=OPENREVIEW_UA)
            if rr:
                try:
                    rd = json.loads(rr)
                    rn = [n for n in rd.get("notes", []) if _get_note_venueid(n)]
                    if rn:
                        paper_notes = rn
                        break
                except json.JSONDecodeError:
                    pass

    if not paper_notes:
        info("No paper results from OpenReview v1 search")
        return None

    candidates, diag = _filter_candidates(paper_notes, title, year)

    if not candidates:
        diag_parts = []
        for k, v in diag.items():
            if v:
                diag_parts.append("{} {}".format(v, k))
        diag_str = " (filtered: {})".format(", ".join(diag_parts)) if diag_parts else ""
        best_ov = max(
            (token_overlap(title, _get_note_title(n)) for n in paper_notes),
            default=0.0
        )
        info("No accepted ICLR paper on OpenReview v1 for year {} (best overlap: {:.2f}){}".format(
            year, best_ov, diag_str
        ))
        return None

    bibtex = _extract_verified_bibtex(candidates, title)
    if bibtex:
        info("source: OpenReview")
        return bibtex

    info("OpenReview v1: all {} candidate(s) failed title verification".format(
        len(candidates)
    ))
    return None


def sanitize_bibtex_key(bibtex):
    # type: (str) -> str
    """Fix illegal BibTeX citation keys (spaces -> underscores)."""
    m = re.match(r"(@\w+\{)([^,]+)(,)", bibtex)
    if m:
        key = m.group(2)
        if " " in key:
            fixed_key = re.sub(r"\s+", "_", key)
            bibtex = m.group(1) + fixed_key + m.group(3) + bibtex[m.end():]
            info("Sanitized BibTeX key: '{}' -> '{}'".format(key, fixed_key))
    return bibtex


def validate_bibtex_fields(bibtex):
    # type: (str) -> None
    """Warn if required BibTeX fields are missing."""
    required = ["author", "title", "year"]
    venue_fields = ["booktitle", "journal"]

    for field in required:
        if not re.search(r"(?<![a-zA-Z])" + field + r"\s*=", bibtex):
            info("WARNING: BibTeX missing required field: {}".format(field))

    has_venue = any(
        re.search(r"(?<![a-zA-Z])" + f + r"\s*=", bibtex) for f in venue_fields
    )
    if not has_venue:
        info("WARNING: BibTeX missing venue field (booktitle or journal)")


def main():
    # type: () -> None
    if len(sys.argv) < 3:
        die('Usage: python3 scripts/iclr_bibtex.py "paper title" "year"')

    title = sys.argv[1].strip()
    year_str = sys.argv[2]

    if not title:
        die("Empty title")

    try:
        year = int(year_str)
    except ValueError:
        die("Invalid year: {}".format(year_str))
        return  # unreachable, satisfies type checker

    if year < MIN_YEAR:
        die("ICLR proceedings on OpenReview start from {}. Got: {}".format(MIN_YEAR, year))

    # Route to the correct API version
    if year >= V2_MIN_YEAR:
        result = search_openreview_v2(title, year)
    else:
        result = search_openreview_v1(title, year)

    if not result:
        die("ICLR BibTeX not found for: {} ({})".format(title, year))
        return  # unreachable, satisfies type checker

    # Post-processing: sanitize and validate before output
    bibtex = sanitize_bibtex_key(result)
    validate_bibtex_fields(bibtex)

    print(bibtex)
    sys.exit(0)


if __name__ == "__main__":
    main()
