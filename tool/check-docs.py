#!/usr/bin/env python3
"""Offline consistency gate for the package's markdown reference.

The docs site ingests `doc/` verbatim at a release tag and validates little on
the way in: a missing page, an empty title or a broken link surfaces only as a
sync warning. This script closes that gap from the repository side. It needs no
network and no Flutter toolchain, so it runs identically in CI and on a
developer machine:

    python3 tool/check-docs.py

Surfaces checked:

1. Page layout and structure: `doc/<section>/<page>.md` with lowercase slug
   names, exactly one H1, and it is the page's opening line, which is the file
   shape `.claude/rules/docs.md` documents.
2. Relative `.md` links resolve to a file that exists inside `doc/`.
3. Fragments (`#section`, both same-file and cross-file) resolve to an explicit
   `<a name>` anchor or a heading slug in the target page.
4. Explicit anchors are reachable from the page's own Table of Contents.
5. Absolute raw-markdown docs URLs on the docs site map to a doc page that
   exists.

The script is a port of wind_kit's `tool/check-docs.py` without the demo
gallery checks (`<x-preview>` tags). A package copying it changes the
constants below and nothing else.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Iterator, NamedTuple
from urllib.parse import unquote, urlsplit

# The docs site serves a page at /dowel/docs/<section>/<page> and its raw
# markdown, for LLMs, at the same URL with .md (site routes/docs.php). The
# package landing, /dowel, sits outside this prefix.
PACKAGE_SLUG = 'tapir'
SITE_ORIGIN = 'https://anilcancakir.com'
DOC_URL_PREFIX = f'/{PACKAGE_SLUG}/docs/'

DOC_ROOT = Path('doc')

# Extra files that carry links into the docs without following the doc/ page
# shape, so they join the link checks but not the structure checks.
EXTRA_LINK_FILES = (
    Path('README.md'),
    Path('CONTRIBUTING.md'),
    Path('SECURITY.md'),
    Path('llms.txt'),
)

# A versioned docs URL such as /dowel/docs/0.0.2/<section>/<page>.md
# resolves against the same doc tree as the unversioned one.
VERSION_SEGMENT = re.compile(r'^v?\d+(?:\.\d+)*(?:-[A-Za-z0-9.]+)?$')

FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})(.*)$')
HEADING = re.compile(r'^(#{1,6})\s+(.+?)\s*$', re.MULTILINE)
ANCHOR = re.compile(r'<a\s+name="([^"]+)"')
INLINE_LINK = re.compile(r'\]\(\s*([^)\s]+)')
REFERENCE_LINK = re.compile(r'^\[[^\]]+\]:\s*(\S+)')
SITE_URL = re.compile(re.escape(SITE_ORIGIN) + r'/[^\s)>"\']+')
PAGE_NAME = re.compile(r'[a-z0-9-]+')


class Issue(NamedTuple):
    """A single failed expectation, addressed to one line of one file."""

    file: Path
    line: int
    message: str

    def as_annotation(self) -> str:
        """Render the issue as a GitHub Actions error annotation."""
        return f'::error file={self.file},line={self.line}::{self.message}'


def blank_fences(text: str) -> str:
    """Blank out fenced code blocks, preserving line offsets.

    A fence closes only on a line that uses the same character, at least as
    many markers as the opening fence, and nothing but whitespace after them
    (CommonMark), so a three-backtick line inside a four-backtick block stays
    part of the block.
    """
    lines: list[str] = []
    opening: tuple[str, int] | None = None

    for line in text.splitlines():
        match = FENCE.match(line)
        if opening is None:
            if match:
                opening = (match.group(1)[0], len(match.group(1)))
            lines.append('' if match else line)
            continue

        lines.append('')
        if (
            match
            and match.group(1)[0] == opening[0]
            and len(match.group(1)) >= opening[1]
            and not match.group(2).strip()
        ):
            opening = None

    return '\n'.join(lines)


def blank_code(text: str) -> str:
    """Blank out fenced and inline code, preserving line and column offsets.

    Doc pages illustrate anchors and links inside code samples. Those are
    documentation about the syntax, not uses of it, so they must not be
    validated. Blanking instead of deleting keeps reported line numbers
    pointing at the real source line.
    """
    # A code span opens with a run of backticks and closes with a run of the
    # same length, so ``[a](b.md)`` is one span, not two empty ones.
    span = re.compile(r'(?<!`)(`+)(?!`).+?(?<!`)\1(?!`)')

    return '\n'.join(
        span.sub(lambda match: ' ' * len(match.group(0)), line)
        for line in blank_fences(text).splitlines()
    )


def slugify(heading: str) -> str:
    """Slugify heading text the way GitHub and the docs site both do.

    Punctuation is dropped and each surviving space becomes one hyphen.
    Whitespace is never collapsed, so `Date + Time` yields `date--time`.
    """
    text = re.sub(r'`([^`]*)`', r'\1', heading)
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = re.sub(r'[^\w\s-]', '', text.strip().lower(), flags=re.UNICODE)

    return text.replace(' ', '-')


def collect_fragments(path: Path) -> set[str]:
    """Collect every fragment a link can target on the given page.

    The union of explicit `<a name>` anchors and heading slugs. Repeated heading
    text gets the `-1`, `-2` suffixes both renderers append.
    """
    text = path.read_text(encoding='utf-8')
    fragments = set(ANCHOR.findall(blank_code(text)))
    seen: dict[str, int] = {}

    # Headings keep their inline code: `## Using `Dowel`` slugs to
    # `using-dowel`, so only fenced blocks are blanked here.
    for _, heading in HEADING.findall(blank_fences(text)):
        slug = slugify(heading)
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        fragments.add(slug if count == 0 else f'{slug}-{count}')

    return fragments


def iter_links(body: str) -> Iterator[tuple[int, str]]:
    """Yield every link target in the body as a (line number, target) pair."""
    for number, line in enumerate(body.splitlines(), 1):
        for target in INLINE_LINK.findall(line):
            yield number, target.strip('<>')
        for target in REFERENCE_LINK.findall(line):
            yield number, target.strip('<>')


def site_url_to_doc(url: str) -> Path | None:
    """Map a raw-markdown docs URL to its source file, or None when not one.

    Both `.../<section>/<page>.md` and the rendered `.../<section>/<page>` URL
    are mapped. A URL with fewer segments, such as `/dowel` or a section
    landing page, may be generated by the site without a backing file, so it is
    out of scope. The test runs against the parsed path, so a link carrying a
    fragment or a query is still validated.
    """
    parts = urlsplit(url)
    if f'{parts.scheme}://{parts.netloc}' != SITE_ORIGIN:
        return None

    path = unquote(parts.path)
    if not path.startswith(DOC_URL_PREFIX):
        return None

    segments = [segment for segment in path[len(DOC_URL_PREFIX):].split('/') if segment]
    if segments and VERSION_SEGMENT.match(segments[0]):
        segments = segments[1:]

    if not segments:
        return None

    if path.endswith('.md'):
        return DOC_ROOT.joinpath(*segments)

    # An extensionless `<section>/<page>` URL is a rendered page backed by
    # `<section>/<page>.md`. A single segment is a section landing page the site
    # generates, and a dotted name is a generated file such as llms.txt. Deeper
    # extensionless URLs match no site route, so they map to a path that cannot
    # exist and are reported.
    if len(segments) >= 2 and '.' not in segments[-1]:
        return DOC_ROOT.joinpath(*segments[:-1], f'{segments[-1]}.md')

    return None


def check_layout(path: Path) -> list[Issue]:
    """Require `doc/<section>/<page>.md` with lowercase slug names.

    The docs site routes `<section>/<page>` with `[a-z0-9-]+` slugs and skips any
    file at another depth or with another name, so such a page passes every other
    check here and never publishes.
    """
    parts = path.relative_to(DOC_ROOT).parts

    if len(parts) != 2:
        return [Issue(path, 1, 'doc pages live at doc/<section>/<page>.md; the docs site skips any other depth')]

    if not all(PAGE_NAME.fullmatch(name) for name in (parts[0], Path(parts[1]).stem)):
        return [Issue(path, 1, 'section and page names are lowercase [a-z0-9-]; the docs site skips any other name')]

    return []


def check_structure(path: Path, raw: str, body: str) -> list[Issue]:
    """Require the page to open with its H1, and to carry exactly one.

    The opening line is measured against the raw text, so anything ahead of the
    title counts as a violation, a lead paragraph and a code fence alike. The H1
    count runs over the code-blanked body, so an illustrative `# Title` inside a
    fenced sample is not mistaken for a second title.
    """
    titles = [
        number
        for number, line in enumerate(body.splitlines(), 1)
        if (match := HEADING.match(line)) and len(match.group(1)) == 1
    ]

    if not titles:
        return [Issue(path, 1, 'no H1 title; the docs site derives the page title from the first H1')]

    issues = [Issue(path, number, 'second H1 on the page; doc pages carry exactly one') for number in titles[1:]]

    opening = next((number for number, line in enumerate(raw.splitlines(), 1) if line.strip()), 1)
    if titles[0] != opening:
        issues.append(Issue(path, opening, 'page does not open with its H1 title'))

    return issues


def check_links(path: Path, body: str, fragments: dict[Path, set[str]]) -> list[Issue]:
    """Resolve relative `.md` targets and every fragment they carry."""
    issues: list[Issue] = []

    for number, target in iter_links(body):
        if target.startswith('#'):
            fragment = target[1:]
            if fragment and fragment not in fragments[path]:
                issues.append(Issue(path, number, f'fragment #{fragment} has no anchor or heading on this page'))
            continue

        if '://' in target or target.startswith(('mailto:', '//')):
            continue

        route, _, fragment = target.partition('#')
        if not route.endswith('.md'):
            continue

        resolved = (path.parent / route).resolve()
        if not resolved.is_file():
            issues.append(Issue(path, number, f'link target {route} does not exist'))
            continue

        # Only doc/ is synced, so the boundary depends on where the link starts.
        # A doc page linking out of doc/ resolves for a GitHub reader and 404s on
        # the site, where that target was never published. README and llms.txt
        # are read on GitHub, so for them the repository is the boundary.
        if path.is_relative_to(DOC_ROOT):
            boundary, label = DOC_ROOT.resolve(), f'{DOC_ROOT}/, which is the only directory the site publishes'
        else:
            boundary, label = Path.cwd(), 'the repository'

        if not resolved.is_relative_to(boundary):
            issues.append(Issue(path, number, f'link target {route} escapes {label}'))
            continue

        relative = resolved.relative_to(Path.cwd())
        if relative not in fragments:
            fragments[relative] = collect_fragments(relative)
        if fragment and fragment not in fragments[relative]:
            issues.append(Issue(path, number, f'fragment #{fragment} does not exist in {route}'))

    return issues


def check_anchor_reachability(path: Path, body: str) -> list[Issue]:
    """Require every explicit anchor to be listed in the page's Table of Contents.

    The ToC is the region above the first section anchor, which covers both page
    shapes: an explicit `## Table of Contents` heading, or a bare bullet list
    under the lead paragraph. Scoping the check to that region is the point:
    counting fragment links from the whole page would let a prose reference deeper
    in the body hide a missing ToC entry, which is the drift this catches.
    """
    lines = body.splitlines()
    first_anchor = next((index for index, line in enumerate(lines) if ANCHOR.search(line)), len(lines))
    listed = {target[1:] for _, target in iter_links('\n'.join(lines[:first_anchor])) if target.startswith('#')}

    return [
        Issue(path, number, f'anchor #{name} is not listed in the Table of Contents')
        for number, line in enumerate(lines, 1)
        for name in ANCHOR.findall(line)
        if name not in listed
    ]


def check_site_urls(path: Path, body: str) -> list[Issue]:
    """Resolve absolute raw-markdown docs URLs against the doc tree."""
    issues: list[Issue] = []

    for number, line in enumerate(body.splitlines(), 1):
        for url in SITE_URL.findall(line):
            target = site_url_to_doc(url.rstrip('.,);'))
            if target is not None and not target.is_file():
                issues.append(Issue(path, number, f'{url} has no source page ({target} is missing)'))

    return issues


def main() -> int:
    """Run every surface over the doc tree and report the combined result."""
    # 1. Page structure and anchor conventions apply to doc/ only; README and
    #    llms.txt legitimately use a different shape.
    doc_pages = sorted(DOC_ROOT.rglob('*.md'))
    if not doc_pages:
        raise SystemExit(f'no markdown found under {DOC_ROOT}/; run this from the repository root.')

    link_files = doc_pages + [path for path in EXTRA_LINK_FILES if path.is_file()]
    fragments: dict[Path, set[str]] = {path: collect_fragments(path) for path in doc_pages}
    issues: list[Issue] = []

    # 2. Link and fragment resolution spans every file that links into the docs.
    for path in link_files:
        body = blank_code(path.read_text(encoding='utf-8'))
        if path not in fragments:
            fragments[path] = collect_fragments(path)
        issues += check_links(path, body, fragments)
        issues += check_site_urls(path, body)

    # 3. The doc-only surfaces: layout, title shape and anchor reachability.
    for path in doc_pages:
        raw = path.read_text(encoding='utf-8')
        body = blank_code(raw)
        issues += check_layout(path)
        issues += check_structure(path, raw, body)
        issues += check_anchor_reachability(path, body)

    for issue in sorted(issues):
        print(issue.as_annotation())

    print(
        f'checked {len(doc_pages)} doc pages + {len(link_files) - len(doc_pages)} linking files: '
        f'{len(issues)} issue(s)',
    )

    return 1 if issues else 0


if __name__ == '__main__':
    sys.exit(main())
