"""Contract tests for the shipped Markdown templates.

The templates under ``platforms/claude/skills/workflows/`` are machine-consumed: codex-flow
parses their bullet lists and loads the paths it finds. Editing one for human readability can
therefore break a codex-flow run with no error — a bullet that no longer resolves as a path is
dropped silently.

Every other test in this suite uses a local fixture, so a template edit passes CI untouched.
These tests parse the real shipped files instead. See
``planning/genai-automations/doc-compaction/observed-failures.md`` for the two failures they guard.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from codex_flow.markdown_parser import _collect_bullets, parse_implementation_request

REPO_ROOT = Path(__file__).resolve().parents[3]
PLANNING_SKILLS = REPO_ROOT / "platforms/claude/skills/workflows/planning"
DESIGN_TEMPLATE = PLANNING_SKILLS / "DESIGN-TEMPLATE.md"
REVIEW_REQUEST_TEMPLATE = PLANNING_SKILLS / "REVIEW-REQUEST-TEMPLATE.md"


def _bullets_under(path: Path, heading_fragment: str) -> list[str]:
    """Collect the bullet list following the first line containing ``heading_fragment``."""
    lines = path.read_text(encoding="utf-8").split("\n")
    for index, line in enumerate(lines):
        if heading_fragment in line:
            return _collect_bullets(lines, index + 1)
    pytest.fail(f"{heading_fragment!r} not found in {path.name}")


@pytest.mark.parametrize("template", [DESIGN_TEMPLATE, REVIEW_REQUEST_TEMPLATE])
def test_template_is_shipped(template: Path) -> None:
    assert template.is_file(), f"{template} is missing — path drifted?"


def test_design_template_context_files_parse_as_paths() -> None:
    """Context Files bullets must survive the parser as usable relative paths.

    A bullet carrying a symbol (``path -> symbol()``) or a pinned locator
    (``<hash>:path:line``) parses into a string that no ``Path.exists()`` check can satisfy,
    so ``codex-flow implement`` receives no context at all.
    """
    bullets = _bullets_under(DESIGN_TEMPLATE, "**Context Files:**")

    assert bullets, "Context Files has no parseable bullets"
    for bullet in bullets:
        assert "→" not in bullet and "->" not in bullet, (
            f"Context Files bullet {bullet!r} carries a symbol arrow; the parser keeps it "
            "verbatim and the path will never resolve"
        )
        assert "`" not in bullet, (
            f"Context Files bullet {bullet!r} still holds a backtick after parsing, so the "
            "path is malformed"
        )
        head = bullet.split(":", 1)[0]
        assert not (len(head) >= 7 and all(c in "0123456789abcdefABCDEF" for c in head)), (
            f"Context Files bullet {bullet!r} looks pinned (<hash>:path:line); the parser "
            "does not strip the prefix and the path will never resolve"
        )
        # I3 / C2: Context Files bullets take no From: tag — that field is reserved for §3
        # requirement bullets. A tag appended here parses as ordinary trailing text (no arrow,
        # no backtick, no hex-looking head), so nothing above this line would catch it.
        assert "From:" not in bullet, (
            f"Context Files bullet {bullet!r} carries a From: tag; §5.2 reserves that field "
            "for requirement bullets and C2 keeps Context Files bare paths"
        )


@pytest.mark.parametrize(
    "heading_fragment",
    ["**Functional Requirements:**", "**Non-Functional Requirements:**", "**Constraints:**"],
)
def test_design_template_requirement_bullets_carry_from_tag(heading_fragment: str) -> None:
    """I2: every §3 requirement bullet must carry an inline From: tag.

    A tag placed on its own line (a bold label opening the line) matches ``FIELD_PATTERN`` and
    breaks ``_collect_bullets()`` — every requirement after it silently vanishes from what
    ``codex-flow implement`` receives, with no error (C3).
    """
    bullets = _bullets_under(DESIGN_TEMPLATE, heading_fragment)

    assert bullets, f"{heading_fragment} has no parseable bullets"
    for bullet in bullets:
        assert "From:" in bullet, (
            f"requirement bullet {bullet!r} under {heading_fragment} carries no From: tag"
        )


def test_design_template_parses_as_implementation_request() -> None:
    """I4: the shipped template is itself a valid, parseable implementation request.

    A From: tag placed on its own line breaks ``_collect_bullets()`` silently — the
    requirement list comes back empty and ``parse_implementation_request()`` raises instead of
    returning a populated request. Parsing the real template end to end proves the whole
    document, not just one bullet list in isolation (the I2 fixture's blast radius).
    """
    request = parse_implementation_request(DESIGN_TEMPLATE)

    assert request.functional_requirements, "no Functional Requirements survived parsing"
    joined = " ".join(request.functional_requirements)
    assert "From:" in joined, "the From: tag text is not present in the parsed requirement"


def test_review_request_constraints_bullets_are_parsed() -> None:
    """Every Constraints bullet must land in the parsed list.

    ``_collect_bullets`` stops at the first blank line once it has collected an item, so a
    bullet separated from the list by a blank line is silently dropped from the structured
    contract even though it still reaches Codex via ``raw_markdown``.
    """
    bullets = _bullets_under(REVIEW_REQUEST_TEMPLATE, "## Constraints")

    assert len(bullets) >= 2, (
        f"expected the placeholder plus the citation-rule bullets, got {bullets!r} — "
        "a blank line between bullets truncates the list"
    )
    joined = " ".join(bullets).lower()
    assert "file and symbol" in joined, (
        "the citation-rule bullet is not in the parsed Constraints list; a blank line "
        "before it puts it outside the list the parser models"
    )
