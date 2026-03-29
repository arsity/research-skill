#!/usr/bin/env python3
"""CVF Open Access BibTeX fetch — golden standard for CVPR/ICCV/WACV (2013+).

Usage: python3 scripts/cvf_bibtex.py "paper title" "author_token" "CVPR|ICCV|WACV" "year"

Constructs CVF Open Access URL from paper metadata, fetches the HTML page,
and extracts the embedded BibTeX. Handles CVF's URL scheme variations:

  URL base path:
    2021+:     /content/{CONF}{YEAR}/html/
    2019-2020: /content_{CONF}_{YEAR}/html/   (uppercase)
    2016-2018: /content_{conf}_{year}/html/   (lowercase)
    2013-2015: /content_{conf}_{year}/html/   (lowercase)

  Filename suffix:
    2016+:     {Author}_{TitleSlug}_{CONF}_{YEAR}_paper.html
    2013-2015: {Author}_{TitleSlug}_{YEAR}_{CONF}_paper.html

  Title truncation:
    2019+:     first 10 words of title
    2013-2018: first 3 words of title

Author contract:
    Pass the exact first-author token CVF uses in the filename/BibTeX key.
    For compound surnames, this is typically the last token (e.g., "Rota Bulo" -> "Bulo").
    Hyphens are preserved (e.g., "Juefei-Xu" stays "Juefei-Xu").

Outputs BibTeX to stdout. Errors as JSON to stderr. Exit 0 on success, 1 on error.
"""

import html as html_mod
import json
import re
import sys
import unicodedata
import urllib.error
import urllib.request
from typing import Optional

BASE_URL = "https://openaccess.thecvf.com"
VALID_CONFS = {"CVPR", "ICCV", "WACV"}
MIN_YEAR = 2013
WACV_MIN_YEAR = 2020
ICCV_YEARS = set(range(2013, 2030, 2))  # odd years only
REQUEST_TIMEOUT = 15


def die(msg: str) -> None:
    print(json.dumps({"error": msg}), file=sys.stderr)
    sys.exit(1)


def info(msg: str) -> None:
    print(json.dumps({"info": msg}), file=sys.stderr)


def normalize_title(title: str) -> str:
    """Normalize a title for comparison: lowercase, alphanumeric only."""
    return re.sub(r"[^a-z0-9]", "", title.lower())


def extract_bibtex_title(bibtex: str) -> Optional[str]:
    """Extract the title field value from a BibTeX entry.

    Handles one level of nested braces (e.g., {Learning {CLIP} Features}).
    Uses negative lookbehind to match 'title' but NOT 'booktitle'.
    """
    match = re.search(r"(?<![a-zA-Z])title\s*=\s*\{((?:[^{}]|\{[^{}]*\})*)\}", bibtex)
    if match:
        # Strip inner braces used for capitalization protection
        title = re.sub(r"\{([^{}]*)\}", r"\1", match.group(1))
        return title.strip()
    return None


def slugify_title(title: str) -> str:
    """Convert paper title to CVF URL slug.

    Rules derived from observed CVF URLs:
    - Remove: colons, semicolons, commas, periods, question marks,
      exclamation marks, quotes, parentheses, brackets, slashes, etc.
    - Replace em/en dashes with hyphens.
    - Replace spaces with underscores.
    - Keep: hyphens, letters, digits.
    """
    s = title
    # Normalize dashes
    s = s.replace("\u2014", "-").replace("\u2013", "-")
    # Unicode NFKD normalization: é→e, ü→u, ñ→n, etc.
    s = unicodedata.normalize("NFKD", s).encode("ascii", errors="ignore").decode("ascii")
    # Remove special characters (keep letters, digits, spaces, hyphens)
    s = re.sub(r"[^a-zA-Z0-9\s\-]", "", s)
    # Collapse whitespace and replace with underscores
    s = re.sub(r"\s+", "_", s.strip())
    # Collapse multiple underscores
    s = re.sub(r"_+", "_", s)
    return s.strip("_")


def truncate_slug(slug: str, max_words: int) -> str:
    """Truncate a slug to max_words underscore-separated tokens."""
    parts = slug.split("_")
    if len(parts) <= max_words:
        return slug
    return "_".join(parts[:max_words])


def build_urls(author: str, title_slug: str, conf: str, year: int) -> list:
    """Build candidate CVF URLs in priority order.

    Generates URLs with year-appropriate base paths and title truncation
    lengths. Tries the most likely pattern first, then fallbacks.
    """
    cu = conf.upper()
    cl = conf.lower()

    # Generate title slugs: full, 10-word, 3-word
    slugs_full = "{}_{}".format(author, title_slug)
    slugs_10 = "{}_{}".format(author, truncate_slug(title_slug, 10))
    slugs_3 = "{}_{}".format(author, truncate_slug(title_slug, 3))

    # Deduplicate while preserving order
    seen = set()  # type: set
    urls = []  # type: list

    def add(url):
        # type: (str) -> None
        if url not in seen:
            seen.add(url)
            urls.append(url)

    if year >= 2021:
        base = "{}/content/{}{}/html".format(BASE_URL, cu, year)
        add("{}/{}_{}_{}_paper.html".format(base, slugs_full, cu, year))
        add("{}/{}_{}_{}_paper.html".format(base, slugs_10, cu, year))
    elif year >= 2019:
        base = "{}/content_{}_{}/html".format(BASE_URL, cu, year)
        add("{}/{}_{}_{}_paper.html".format(base, slugs_full, cu, year))
        add("{}/{}_{}_{}_paper.html".format(base, slugs_10, cu, year))
    elif year >= 2016:
        base = "{}/content_{}_{}/html".format(BASE_URL, cl, year)
        add("{}/{}_{}_{}_paper.html".format(base, slugs_3, cu, year))
        add("{}/{}_{}_{}_paper.html".format(base, slugs_full, cu, year))
        # Some ICCV years use uppercase base inconsistently
        base_upper = "{}/content_{}_{}/html".format(BASE_URL, cu, year)
        add("{}/{}_{}_{}_paper.html".format(base_upper, slugs_3, cu, year))
        add("{}/{}_{}_{}_paper.html".format(base_upper, slugs_full, cu, year))
    else:  # 2013-2015
        base = "{}/content_{}_{}/html".format(BASE_URL, cl, year)
        # CVPR 2013-2015 uses YEAR_CONF suffix; ICCV 2015 uses CONF_YEAR.
        # Try both orders to handle conference-specific conventions.
        add("{}/{}_{}_{}_paper.html".format(base, slugs_3, year, cu))
        add("{}/{}_{}_{}_paper.html".format(base, slugs_3, cu, year))
        add("{}/{}_{}_{}_paper.html".format(base, slugs_full, year, cu))
        add("{}/{}_{}_{}_paper.html".format(base, slugs_full, cu, year))

    return urls


def extract_bibtex(html_content: str) -> Optional[str]:
    """Extract BibTeX from CVF paper HTML page.

    CVF embeds BibTeX in <div class="bibref ...">...</div>.
    Newer pages use whitespace formatting; older pages use <br> tags.
    """
    match = re.search(
        r'<div\s+class="bibref[^"]*">(.*?)</div>',
        html_content,
        re.DOTALL,
    )
    if not match:
        return None

    bibtex = match.group(1)
    # Strip HTML tags (<br>, <br/>, etc.)
    bibtex = re.sub(r"<br\s*/?>", "\n", bibtex)
    bibtex = re.sub(r"<[^>]+>", "", bibtex)
    # Decode all HTML entities
    bibtex = html_mod.unescape(bibtex)
    bibtex = bibtex.strip()

    if not bibtex.startswith("@"):
        return None
    return bibtex


def fetch_url(url: str) -> Optional[str]:
    """Fetch URL, return body on 2xx, None otherwise.

    urllib raises HTTPError for 4xx/5xx before entering the with block,
    so only 2xx responses reach the read() call.
    """
    req = urllib.request.Request(url, headers={"User-Agent": "research-skill/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        if e.code not in (404, 410):
            info("CVF HTTP {} for {}".format(e.code, url))
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        info("CVF connection error for {}: {}".format(url, e))
    return None


def main() -> None:
    if len(sys.argv) < 5:
        die(
            'Usage: python3 scripts/cvf_bibtex.py "paper title" '
            '"first_author_lastname" "CVPR|ICCV|WACV" "year"'
        )

    title = sys.argv[1]
    author = sys.argv[2]
    conf = sys.argv[3].upper()

    year_str = sys.argv[4]
    try:
        year = int(year_str)
    except ValueError:
        die("Invalid year: {}".format(year_str))
        return  # unreachable, but satisfies type checker

    if conf not in VALID_CONFS:
        die("Unsupported conference: {} (must be CVPR, ICCV, or WACV)".format(conf))
    if conf == "WACV" and year < WACV_MIN_YEAR:
        die("WACV on CVF Open Access starts from {}. Got: {}".format(WACV_MIN_YEAR, year))
    if conf == "ICCV" and year not in ICCV_YEARS:
        info("ICCV is held in odd years only. {} may not exist.".format(year))
    if year < MIN_YEAR:
        die("CVF Open Access only available from {}. Got: {}".format(MIN_YEAR, year))

    title_slug = slugify_title(title)
    urls = build_urls(author, title_slug, conf, year)

    for url in urls:
        html_content = fetch_url(url)
        if html_content is None:
            continue
        bibtex = extract_bibtex(html_content)
        if not bibtex:
            continue

        # Title verification: ensure the fetched paper matches the requested title
        fetched_title = extract_bibtex_title(bibtex)
        if not fetched_title:
            info("CVF BibTeX has no parseable title field. Skipping.")
            continue
        if normalize_title(fetched_title) != normalize_title(title):
            info(
                "CVF title mismatch: requested '{}', got '{}'. Skipping.".format(
                    title, fetched_title
                )
            )
            continue

        print(bibtex)
        sys.exit(0)

    die("CVF BibTeX not found for: {} ({} {})".format(title, conf, year))


if __name__ == "__main__":
    main()
