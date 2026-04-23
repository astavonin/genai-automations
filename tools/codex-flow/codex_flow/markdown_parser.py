"""Markdown contract parsing for codex-flow request files."""

from __future__ import annotations

import re
from pathlib import Path

from .contracts import ImplementationRequest, ReviewRequest, SUPPORTED_LANGUAGES
from .exceptions import ValidationError

FIELD_PATTERN = re.compile(r"^\*\*(?P<name>[^*]+):\*\*\s*(?P<value>.*)$")
HEADING_PATTERN = re.compile(r"^(?P<level>#+)\s+(?P<title>.+?)\s*$")


def parse_implementation_request(request_path: Path) -> ImplementationRequest:
    """Parse and validate an implementation request document."""
    text = _read_text(request_path)
    lines = text.splitlines()

    title = _find_first_heading(lines)
    if not title.startswith("Design"):
        raise ValidationError("Implementation request must start with a Design heading.")

    section = _extract_section(lines, "Implementation Context")
    repository = _require_absolute_path(_extract_field(section, "Repository"), "Repository")
    language = _extract_field(section, "Language").strip("`").lower()
    if language not in SUPPORTED_LANGUAGES:
        raise ValidationError(
            f"Language must be one of {sorted(SUPPORTED_LANGUAGES)}; got {language!r}."
        )

    requirements = _extract_bullets_after_field(section, "Requirements")
    constraints = _extract_bullets_after_field(section, "Constraints")
    verification = _extract_code_block_after_field(section, "Verification")
    context_files = _extract_bullets_after_field(section, "Context Files")

    if not requirements:
        raise ValidationError("Implementation request must include at least one requirement.")
    if not verification.strip():
        raise ValidationError("Implementation request must include a non-empty Verification block.")

    return ImplementationRequest(
        request_path=request_path.resolve(),
        repository=repository,
        language=language,
        requirements=requirements,
        constraints=constraints,
        verification=verification.strip(),
        context_files=context_files,
        raw_markdown=text,
    )


def parse_review_request(request_path: Path) -> ReviewRequest:
    """Parse and validate a review request document."""
    text = _read_text(request_path)
    lines = text.splitlines()

    title = _find_first_heading(lines)
    if not title.startswith("Review Request"):
        raise ValidationError("Review request must start with a Review Request heading.")

    repository = _require_absolute_path(_extract_global_field(lines, "Repository"), "Repository")
    review_scope = _extract_global_field(lines, "Review Scope")
    if not review_scope:
        raise ValidationError("Review Scope must not be empty.")

    output_file = _extract_global_field(lines, "Output File")
    if not output_file:
        raise ValidationError("Output File is required for review requests.")

    branch = _optional_global_field(lines, "Branch")
    date = _optional_global_field(lines, "Date")
    requirements = _extract_bullets_in_section(lines, "Requirements")
    constraints = _extract_bullets_in_section(lines, "Constraints")
    evidence = _extract_code_block_in_section(lines, "Evidence")
    review_focus = _extract_bullets_in_section(lines, "Review Focus")

    if not requirements:
        raise ValidationError("Review request must include at least one requirement.")
    if not constraints:
        raise ValidationError("Review request must include at least one constraint.")
    if not evidence.strip():
        raise ValidationError("Review request must include a non-empty Evidence block.")
    if not review_focus:
        raise ValidationError("Review request must include at least one Review Focus item.")

    request = ReviewRequest(
        request_path=request_path.resolve(),
        repository=repository,
        branch=branch,
        review_scope=review_scope,
        output_file=output_file,
        date=date,
        requirements=requirements,
        constraints=constraints,
        evidence=evidence.strip(),
        review_focus=review_focus,
        raw_markdown=text,
    )
    try:
        _ = request.output_path
    except ValueError as err:
        raise ValidationError(str(err)) from err
    return request


def _read_text(path: Path) -> str:
    if not path.exists():
        raise ValidationError(f"Request file not found: {path}")
    return path.read_text(encoding="utf-8")


def _find_first_heading(lines: list[str]) -> str:
    for line in lines:
        match = HEADING_PATTERN.match(line)
        if match and len(match.group("level")) == 1:
            return match.group("title").strip()
    raise ValidationError("Request must contain a top-level heading.")


def _extract_section(lines: list[str], heading: str) -> list[str]:
    found = False
    collected: list[str] = []
    for line in lines:
        match = HEADING_PATTERN.match(line)
        if match and len(match.group("level")) == 2:
            title = _normalize_heading(match.group("title"))
            if found:
                break
            if title == heading:
                found = True
                continue
        if found:
            collected.append(line)
    if not found:
        raise ValidationError(f"Missing required section: {heading}")
    return collected


def _extract_field(lines: list[str], name: str) -> str:
    for line in lines:
        match = FIELD_PATTERN.match(line.strip())
        if match and match.group("name").strip() == name:
            return match.group("value").strip()
    raise ValidationError(f"Missing required field: {name}")


def _optional_global_field(lines: list[str], name: str) -> str | None:
    try:
        return _extract_global_field(lines, name)
    except ValidationError:
        return None


def _extract_global_field(lines: list[str], name: str) -> str:
    value = _extract_field(lines, name)
    if not value:
        raise ValidationError(f"Field must not be empty: {name}")
    return value.strip("`")


def _extract_bullets_after_field(lines: list[str], name: str) -> list[str]:
    start = _line_index_for_field(lines, name)
    return _collect_bullets(lines, start + 1)


def _extract_bullets_in_section(lines: list[str], heading: str) -> list[str]:
    section = _extract_section(lines, heading)
    return _collect_bullets(section, 0)


def _extract_code_block_after_field(lines: list[str], name: str) -> str:
    start = _line_index_for_field(lines, name)
    return _collect_code_block(lines, start + 1)


def _extract_code_block_in_section(lines: list[str], heading: str) -> str:
    section = _extract_section(lines, heading)
    return _collect_code_block(section, 0)


def _line_index_for_field(lines: list[str], name: str) -> int:
    for index, line in enumerate(lines):
        match = FIELD_PATTERN.match(line.strip())
        if match and match.group("name").strip() == name:
            return index
    raise ValidationError(f"Missing required field: {name}")


def _collect_bullets(lines: list[str], start: int) -> list[str]:
    items: list[str] = []
    for raw_line in lines[start:]:
        line = raw_line.strip()
        if not line:
            if items:
                break
            continue
        if HEADING_PATTERN.match(line) or FIELD_PATTERN.match(line):
            break
        if line.startswith("- "):
            items.append(line[2:].strip().strip("`"))
            continue
        if items:
            break
    return items


def _collect_code_block(lines: list[str], start: int) -> str:
    in_block = False
    block_lines: list[str] = []
    for raw_line in lines[start:]:
        line = raw_line.rstrip("\n")
        stripped = line.strip()
        if not in_block:
            if stripped.startswith("```"):
                in_block = True
            elif stripped:
                if HEADING_PATTERN.match(stripped) or FIELD_PATTERN.match(stripped):
                    break
            continue
        if stripped.startswith("```"):
            return "\n".join(block_lines).strip()
        block_lines.append(line)
    raise ValidationError("Expected fenced code block.")


def _require_absolute_path(value: str, field_name: str) -> Path:
    cleaned = value.strip("`")
    path = Path(cleaned)
    if not path.is_absolute():
        raise ValidationError(f"{field_name} must be an absolute path.")
    return path.resolve()


def _normalize_heading(title: str) -> str:
    normalized = title.strip()
    return re.sub(r"^\d+(?:\.\d+)*\.\s+", "", normalized)
