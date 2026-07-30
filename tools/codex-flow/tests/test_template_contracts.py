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

from codex_flow.markdown_parser import _collect_bullets

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
