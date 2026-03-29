#!/usr/bin/env python3
"""NeurIPS BibTeX fetch — golden standard for NeurIPS/NIPS papers.

Usage: python3 scripts/neurips_bibtex.py "paper title" "year"

Two-source strategy:
  1. papers.nips.cc (official proceedings, 1987-2024)
     Search by title -> extract paper hash -> fetch {hash}-Bibtex.bib
     Quality: complete (author, booktitle, editor, pages, publisher, volume, year)

  2. OpenReview API v2 (fallback, NeurIPS 2023+)
     Search by title -> filter by NeurIPS venue + year -> extract _bibtex
     Quality: minimal (title, author, booktitle, year, url)

papers.nips.cc is preferred when available (richer metadata).
OpenReview is used for years not yet on nips.cc (e.g., 2025).

Source identification:
  Outputs {"info": "source: nips.cc"} or {"info": "source: OpenReview"} to stderr
  so the calling workflow can set the appropriate tag.

Outputs BibTeX to stdout. Errors as JSON to stderr. Exit 0 on success, 1 on error.
"""

import html as html_mod
import json
import re
import sys
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from typing import Optional

NIPS_BASE = "https://papers.nips.cc"
# 2021 D&B track has its own proceedings site (only year on this site)
NIPS_DB_BASE = "https://datasets-benchmarks-proceedings.neurips.cc"
OPENREVIEW_API = "https://api2.openreview.net"
MIN_YEAR = 1987
REQUEST_TIMEOUT = 15
USER_AGENT = "research-skill/1.0"
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
    """NFKD Unicode decomposition → ASCII. é→e, ü→u, ñ→n, etc.

    Handles characters that NFKD doesn't decompose to ASCII:
    ß→ss, ø→o, Ø→O, æ→ae, Æ→AE, œ→oe, Œ→OE, ð→d, þ→th, ł→l, Ł→L.
    """
    # Pre-map characters that NFKD doesn't decompose to ASCII
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
    """Normalize for comparison: strip LaTeX, fold Unicode, lowercase, alphanumeric only.

    Handles BibTeX TeX escapes (\\textemdash, \\textendash, \\', \\`)
    and Unicode variants (em-dash, en-dash, accented characters).

    Processing order matters:
    1. Replace LaTeX dash commands with space FIRST (before generic strip)
       to prevent word concatenation (e.g., Vision\\textendashLanguage)
    2. Replace Unicode dashes with space
    3. Remove LaTeX accent commands (\\'e → e, \\`a → a)
    4. ASCII-fold remaining Unicode
    5. Keep only alphanumeric
    """
    s = title
    # 1. Replace LaTeX dash commands with space (must be before generic strip
    #    because \\textendashLanguage would otherwise eat 'Language' too)
    s = re.sub(r"\\textemdash", " ", s)
    s = re.sub(r"\\textendash", " ", s)
    # 2. Replace Unicode em/en dashes with space
    s = s.replace("\u2014", " ").replace("\u2013", " ")
    # 3. Replace LaTeX character macros with ASCII equivalents
    s = s.replace("\\ss", "ss")     # ß
    s = s.replace("\\o", "o")       # ø (must be before generic accent strip)
    s = s.replace("\\O", "O")       # Ø
    s = s.replace("\\ae", "ae")     # æ
    s = s.replace("\\AE", "AE")     # Æ
    s = s.replace("\\oe", "oe")     # œ
    s = s.replace("\\OE", "OE")     # Œ
    s = s.replace("\\l", "l")       # ł
    s = s.replace("\\L", "L")       # Ł
    # 4. Remove LaTeX accent commands: \' \` \" \^ \~ \= \. \H \u \v \c \d \b \t
    s = re.sub(r"\\['\"`^~=.Huvcdbtr]", "", s)
    # 4. Unicode NFKD normalization: é→e, ü→u, etc.
    s = ascii_fold(s)
    # 5. Keep only lowercase alphanumeric
    return re.sub(r"[^a-z0-9]", "", s.lower())


def _normalize_for_tokens(s):
    # type: (str) -> str
    """Normalize Unicode punctuation to ASCII for consistent tokenization.

    Replaces smart quotes, dashes, and other Unicode punctuation with ASCII
    equivalents so that 'Don\u2019t' matches 'Don't', etc.
    """
    # Smart quotes → ASCII
    s = s.replace("\u2018", "'").replace("\u2019", "'")  # left/right single
    s = s.replace("\u201c", '"').replace("\u201d", '"')   # left/right double
    # Dashes → hyphen
    s = s.replace("\u2014", "-").replace("\u2013", "-")
    return s


def token_overlap(a, b):
    # type: (str, str) -> float
    """Jaccard token overlap between two titles.

    Normalizes Unicode punctuation before tokenizing so that
    'Don\u2019t' and 'Don't' are treated as the same token.
    """
    ta = set(_normalize_for_tokens(a).lower().split())
    tb = set(_normalize_for_tokens(b).lower().split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def extract_bibtex_title(bibtex):
    # type: (str) -> Optional[str]
    """Extract title field from BibTeX.

    Uses negative lookbehind to match 'title' but NOT 'booktitle'.
    Supports arbitrary brace nesting depth via manual brace counting
    instead of regex (regex can only handle fixed nesting levels).
    """
    # Find 'title = {' (not 'booktitle')
    m = re.search(r"(?<![a-zA-Z])title\s*=\s*\{", bibtex)
    if not m:
        return None

    # Manual brace-counting to extract content with arbitrary nesting
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
    # Strip inner braces used for capitalization protection
    title = re.sub(r"\{([^{}]*)\}", r"\1", title)
    return title.strip()


def fetch_url(url, accept="text/html", ua=None):
    # type: (str, str, Optional[str]) -> Optional[str]
    """Fetch URL, return body on 2xx, None otherwise."""
    req = urllib.request.Request(url, headers={
        "User-Agent": ua or USER_AGENT,
        "Accept": accept,
    })
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        if e.code not in (404, 410):
            info("HTTP {} for {}".format(e.code, url))
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        info("Connection error for {}: {}".format(url, e))
    return None


def search_nips_cc(title, year):
    # type: (str, int) -> Optional[str]
    """Search NeurIPS proceedings sites by title, return BibTeX if found.

    Searches two sites:
    - papers.nips.cc: main conference (1987-2024) + D&B track (2022+)
    - datasets-benchmarks-proceedings.neurips.cc: D&B track 2021 only

    Steps:
    1. Search by title via /papers/search?q=
    2. Parse HTML results for paper links containing /hash/{32-char-hex}-
    3. Filter by year, match by title similarity (>= 0.90 Jaccard)
    4. Fetch {hash}-Bibtex.bib
    5. Title-verify the fetched BibTeX
    """
    query = urllib.parse.quote(title)
    url = "{}/papers/search?q={}".format(NIPS_BASE, query)

    html = fetch_url(url)

    # If title has non-ASCII characters (accented, Unicode), also try
    # ASCII-folded query — nips.cc search may not index accented chars well.
    # Replace em/en dashes with spaces before folding to prevent word concatenation.
    folded = ascii_fold(title.replace("\u2014", " ").replace("\u2013", " "))
    if folded != title:
        query2 = urllib.parse.quote(folded)
        url2 = "{}/papers/search?q={}".format(NIPS_BASE, query2)
        html2 = fetch_url(url2)
        if html2:
            html = (html or "") + html2

    # If still no results, try content-words-only search (drop short words
    # that may cause search engine issues, e.g., "Deja" from "Déjà").
    # Use len > 4 to keep only distinctive words — short words from Unicode
    # folding (e.g., Déjà→Deja) often confuse the search engine.
    if html and not re.search(r'/hash/[a-f0-9]{32}', html):
        content_words = [w for w in folded.split() if len(w) > 4]
        if content_words:
            query3 = urllib.parse.quote(" ".join(content_words))
            url3 = "{}/papers/search?q={}".format(NIPS_BASE, query3)
            html3 = fetch_url(url3)
            if html3:
                html = html + html3

    # Also search the D&B proceedings site (datasets-benchmarks-proceedings.neurips.cc)
    # which hosts 2021 D&B track papers that aren't on the main site.
    for db_query in [query, urllib.parse.quote(folded)]:
        db_url = "{}/papers/search?q={}".format(NIPS_DB_BASE, db_query)
        db_html = fetch_url(db_url)
        if db_html and re.search(r'/hash/[a-f0-9]{32}', db_html):
            # Rewrite relative URLs to absolute so BibTeX fetch uses correct host
            db_html = db_html.replace(
                'href="/paper_files/', 'href="{}/paper_files/'.format(NIPS_DB_BASE)
            )
            html = (html or "") + db_html
            break

    if not html:
        info("nips.cc search request failed")
        return None

    # Extract paper links: href contains /paper[_files]/paper/{year}/hash/{hash}-...
    # The search results page has <a> tags linking to paper abstract pages.
    # Matches both relative (/paper_files/...) and absolute (https://.../) hrefs.
    results = re.findall(
        r'href="((?:https?://[^/]+)?/paper(?:_files)?/paper/(\d{4})/hash/([a-f0-9]{32})-[^"]*)"'
        r'[^>]*>\s*(.*?)\s*</a>',
        html, re.DOTALL | re.IGNORECASE
    )

    if not results:
        info("No results from nips.cc search")
        return None

    # Filter by year and collect candidates sorted by title overlap (descending).
    # Try each candidate until one passes exact title verification — the best
    # Jaccard match may have a slightly different BibTeX title due to HTML
    # entities, truncation, or search-result formatting differences.
    candidates = []  # type: list  # [(hash, clean_title, overlap)]

    for _, result_year, paper_hash, result_title in results:
        if int(result_year) != year:
            continue
        # Strip HTML tags and unescape entities (e.g., &amp; → &, &#39; → ')
        clean = html_mod.unescape(re.sub(r"<[^>]+>", "", result_title)).strip()
        if not clean:
            continue
        ov = token_overlap(title, clean)
        if ov >= 0.90:
            candidates.append((paper_hash, clean, ov))

    if not candidates:
        # Report best sub-threshold overlap for diagnostics
        best_ov = 0.0
        for _, result_year, _, result_title in results:
            if int(result_year) != year:
                continue
            clean = re.sub(r"<[^>]+>", "", result_title).strip()
            if clean:
                best_ov = max(best_ov, token_overlap(title, clean))
        info("No matching paper on nips.cc for year {} (best overlap: {:.2f})".format(
            year, best_ov
        ))
        return None

    # Sort by overlap descending — try best match first
    candidates.sort(key=lambda x: x[2], reverse=True)

    for paper_hash, _, _ in candidates:
        # Fetch BibTeX .bib file — try main site first, then D&B site
        bibtex = None
        for base in [NIPS_BASE, NIPS_DB_BASE]:
            bib_url = "{}/paper_files/paper/{}/file/{}-Bibtex.bib".format(
                base, year, paper_hash
            )
            bibtex = fetch_url(bib_url, accept="text/plain")
            if bibtex:
                break
        if not bibtex:
            continue

        bibtex = bibtex.strip()
        if not bibtex.startswith("@"):
            continue

        # Title verification: ensure BibTeX title matches requested title
        bib_title = extract_bibtex_title(bibtex)
        if not bib_title:
            continue
        if normalize_title(bib_title) != normalize_title(title):
            info("nips.cc title mismatch: requested '{}', got '{}'".format(
                title, bib_title
            ))
            continue

        info("source: nips.cc")
        return bibtex

    info("nips.cc: all {} candidate(s) failed title verification".format(
        len(candidates)
    ))
    return None


def _get_note_title(note):
    # type: (dict) -> str
    """Extract title string from an OpenReview note (handles dict or str)."""
    t = note.get("content", {}).get("title", {})
    if isinstance(t, dict):
        return t.get("value", "")
    return str(t) if t else ""


def search_openreview(title, year):
    # type: (str, int) -> Optional[str]
    """Search OpenReview API v2 by title, return BibTeX if found.

    Steps:
    1. Search via /notes/search?query=&source=forum
    2. Filter by NeurIPS venue ID + year (skip DBLP-indexed duplicates)
    3. Match by title similarity (>= 0.90 Jaccard)
    4. Extract _bibtex field from matched note
    5. Title-verify the BibTeX
    """
    # Use quote_plus for query params (spaces as +); OpenReview's search
    # backend returns 400 for some %20-encoded queries.
    query = urllib.parse.quote_plus(title)
    url = "{}/notes/search?query={}&source=forum&limit=10".format(
        OPENREVIEW_API, query
    )

    resp = fetch_url(url, accept="application/json", ua=OPENREVIEW_UA)

    # OpenReview returns transient 400 SearchErrors. Retry strategy:
    # 1. Always retry the same query once (handles pure transient failures)
    # 2. If still failing, retry with simplified query (drop short tokens)
    if resp is None:
        resp = fetch_url(url, accept="application/json", ua=OPENREVIEW_UA)
    # Try ASCII-folded query (accented chars cause 400 on OpenReview)
    if resp is None:
        folded = ascii_fold(title.replace("\u2014", " ").replace("\u2013", " "))
        query_f = urllib.parse.quote_plus(folded)
        url_f = "{}/notes/search?query={}&source=forum&limit=10".format(
            OPENREVIEW_API, query_f
        )
        resp = fetch_url(url_f, accept="application/json", ua=OPENREVIEW_UA)
    # Last resort: content words only (drop short tokens)
    if resp is None:
        folded = ascii_fold(title.replace("\u2014", " ").replace("\u2013", " "))
        words = [w for w in folded.split() if len(w) > 3]
        query2 = urllib.parse.quote_plus(" ".join(words))
        url2 = "{}/notes/search?query={}&source=forum&limit=10".format(
            OPENREVIEW_API, query2
        )
        resp = fetch_url(url2, accept="application/json", ua=OPENREVIEW_UA)
    if not resp:
        info("OpenReview search request failed")
        return None

    try:
        data = json.loads(resp)
    except json.JSONDecodeError:
        info("OpenReview returned invalid JSON")
        return None

    notes = data.get("notes", [])

    # If 200 OK but empty results, retry with ASCII-folded/simplified query
    if not notes:
        folded = ascii_fold(title.replace("\u2014", " ").replace("\u2013", " "))
        for retry_query in [folded, " ".join(w for w in folded.split() if len(w) > 4)]:
            if not retry_query.strip():
                continue
            rq = urllib.parse.quote_plus(retry_query)
            ru = "{}/notes/search?query={}&source=forum&limit=10".format(
                OPENREVIEW_API, rq
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
        info("No results from OpenReview search")
        return None

    # Collect candidates sorted by overlap, try each until title-verified.
    candidate_notes = []  # type: list  # [(note, overlap)]

    for note in notes:
        content = note.get("content", {})

        # Get venue ID — may be string or {"value": "..."}
        vid = content.get("venueid", {})
        if isinstance(vid, dict):
            vid = vid.get("value", "")
        if not vid:
            continue

        # Skip DBLP-indexed entries (duplicates with different BibTeX format)
        if vid.startswith("dblp.org/"):
            continue

        # Exact venueid allowlist for accepted NeurIPS proceedings.
        # Accepted papers live under these venueids:
        #   NeurIPS.cc/{year}/Conference
        #   NeurIPS.cc/{year}/Datasets_and_Benchmarks_Track
        # Everything else (Position_Paper_Track, Workshop/*, Rejected,
        # Withdrawn, etc.) is excluded.
        accepted_vids = [
            "NeurIPS.cc/{}/Conference".format(year),
            "NeurIPS.cc/{}/Datasets_and_Benchmarks_Track".format(year),
        ]
        if vid not in accepted_vids:
            continue

        # Venue string check: accepted papers have venue like
        # "NeurIPS 2025 Poster/Oral/Spotlight" or "NeurIPS 2025 D&B Poster".
        # Reject "Submitted to NeurIPS" (non-accepted).
        venue_val = content.get("venue", {})
        if isinstance(venue_val, dict):
            venue_val = venue_val.get("value", "")
        if venue_val and not re.search(
            r"neurips\s+\d{4}\s+.*(poster|oral|spotlight)",
            str(venue_val), re.IGNORECASE
        ):
            continue

        # Get title — may be string or {"value": "..."}
        nt = content.get("title", {})
        if isinstance(nt, dict):
            nt = nt.get("value", "")
        if not nt:
            continue

        ov = token_overlap(title, nt)
        if ov >= 0.90:
            candidate_notes.append((note, ov))

    if not candidate_notes:
        info("No matching NeurIPS paper on OpenReview (best overlap: {:.2f})".format(
            max((token_overlap(title, _get_note_title(n)) for n in notes), default=0.0)
        ))
        return None

    # Sort by overlap descending — try best match first
    candidate_notes.sort(key=lambda x: x[1], reverse=True)

    for note, _ in candidate_notes:
        # Extract BibTeX from _bibtex field
        content = note.get("content", {})
        bib_field = content.get("_bibtex", {})
        if isinstance(bib_field, dict):
            bibtex = bib_field.get("value", "")
        else:
            bibtex = str(bib_field) if bib_field else ""

        bibtex = bibtex.strip()
        if not bibtex.startswith("@"):
            continue

        # Title verification
        bib_title = extract_bibtex_title(bibtex)
        if not bib_title:
            continue
        if normalize_title(bib_title) != normalize_title(title):
            info("OpenReview title mismatch: requested '{}', got '{}'".format(
                title, bib_title
            ))
            continue

        # Fail closed: accepted papers use @inproceedings, not @misc.
        # @misc indicates a non-published submission — do NOT return it.
        if bibtex.startswith("@misc"):
            info("Rejecting @misc BibTeX — accepted papers use @inproceedings")
            continue

        info("source: OpenReview")
        return bibtex

    info("OpenReview: all {} candidate(s) failed title verification".format(
        len(candidate_notes)
    ))
    return None


def sanitize_bibtex_key(bibtex):
    # type: (str) -> str
    """Fix illegal BibTeX citation keys.

    The D&B proceedings site produces keys with spaces like:
    @inproceedings{NEURIPS DATASETS AND BENCHMARKS2021_013d4071,
    Spaces in BibTeX keys are illegal and break \\cite{} in LaTeX.
    Replace spaces with underscores.
    """
    # Match the key: @type{KEY, — capture and fix the KEY part
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
    """Warn if required BibTeX fields are missing.

    Required for desk-reject prevention: author, title, year, booktitle/journal.
    Does not block output (the source is authoritative), but warns via stderr.
    """
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
        die('Usage: python3 scripts/neurips_bibtex.py "paper title" "year"')

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
        die("NeurIPS/NIPS proceedings start from {}. Got: {}".format(MIN_YEAR, year))

    # Strategy: try nips.cc first (richer BibTeX), fall back to OpenReview
    bibtex = search_nips_cc(title, year)

    if not bibtex:
        bibtex = search_openreview(title, year)

    if not bibtex:
        die("NeurIPS BibTeX not found for: {} ({})".format(title, year))
        return  # unreachable, satisfies type checker

    # Post-processing: sanitize and validate before output
    bibtex = sanitize_bibtex_key(bibtex)
    validate_bibtex_fields(bibtex)

    print(bibtex)
    sys.exit(0)


if __name__ == "__main__":
    main()
