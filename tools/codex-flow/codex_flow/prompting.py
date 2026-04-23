"""Prompt assembly and bundled workflow resources."""

from __future__ import annotations

import json
from importlib import resources
from pathlib import Path

from .contracts import ImplementationRequest, ReviewRequest

RESOURCE_ROOT = "codex_flow.resources"

IMPLEMENTATION_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "final_status",
        "summary",
        "files_changed",
        "verification_results",
        "reasoning",
        "open_issues",
    ],
    "properties": {
        "final_status": {
            "type": "string",
            "enum": ["SUCCESS", "NEEDS CLARIFICATION", "FAILED"],
        },
        "summary": {"type": "string"},
        "files_changed": {"type": "array", "items": {"type": "string"}},
        "verification_results": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["command", "status", "details"],
                "properties": {
                    "command": {"type": "string"},
                    "status": {"type": "string"},
                    "details": {"type": "string"},
                },
            },
        },
        "reasoning": {"type": "array", "items": {"type": "string"}},
        "open_issues": {"type": "array", "items": {"type": "string"}},
    },
}

REVIEW_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": [
        "final_status",
        "summary",
        "findings",
        "requirement_coverage",
        "verification_gaps",
        "recommendation",
    ],
    "properties": {
        "final_status": {
            "type": "string",
            "enum": ["APPROVE", "REQUEST CHANGES", "INFORMATIONAL"],
        },
        "summary": {"type": "string"},
        "findings": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["severity", "title", "evidence", "recommendation"],
                "properties": {
                    "severity": {"type": "string"},
                    "title": {"type": "string"},
                    "evidence": {"type": "string"},
                    "recommendation": {"type": "string"},
                },
            },
        },
        "requirement_coverage": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["requirement", "status", "notes"],
                "properties": {
                    "requirement": {"type": "string"},
                    "status": {"type": "string"},
                    "notes": {"type": "string"},
                },
            },
        },
        "verification_gaps": {"type": "array", "items": {"type": "string"}},
        "recommendation": {"type": "string"},
    },
}


def load_schema(mode: str) -> dict:
    """Return the JSON schema for the selected mode."""
    if mode == "implement":
        return IMPLEMENTATION_SCHEMA
    if mode == "review":
        return REVIEW_SCHEMA
    raise ValueError(f"Unsupported mode: {mode}")


def build_implementation_prompt(request: ImplementationRequest) -> str:
    """Create the Codex prompt for implementation mode."""
    skill_text = "\n\n".join(
        [
            _resource_text("skills/CODEX.md"),
            _resource_text("skills/workflows/external-implementation/SKILL.md"),
            _resource_text("skills/coder/SKILL.md"),
            _resource_text("skills/domains/code-quality/SKILL.md"),
            _resource_text("skills/domains/testing/SKILL.md"),
            _resource_text("templates/implementation-output-instructions.md"),
        ]
    )

    context_blocks = []
    for relative_path in request.context_files:
        target = request.repository / relative_path
        if target.exists():
            context_blocks.append(_file_block(target, relative_path))

    return "\n\n".join(
        [
            "You are running codex-flow in implementation mode.",
            "Apply the request inside the target repository, keep the change surface minimal, run the"
            " listed verification commands in order, and return only JSON matching the provided schema.",
            "The runner writes the Markdown artifact; do not try to write the output document yourself.",
            "Bundled workflow guidance:",
            skill_text,
            "Authoritative request document:",
            request.raw_markdown.strip(),
            "Loaded context files:",
            "\n\n".join(context_blocks) if context_blocks else "(No context files were provided.)",
        ]
    )


def build_review_prompt(request: ReviewRequest) -> str:
    """Create the Codex prompt for review mode."""
    skill_parts = [
        _resource_text("skills/CODEX.md"),
        _resource_text("skills/workflows/code-review/SKILL.md"),
        _resource_text("skills/reviewer/SKILL.md"),
        _resource_text("skills/domains/quality-attributes/SKILL.md"),
        _resource_text("templates/review-output-instructions.md"),
    ]

    language = _detect_language(request.repository)
    if language:
        skill_parts.append(_resource_text(f"skills/languages/{language}.md"))

    return "\n\n".join(
        [
            "You are running codex-flow in review mode.",
            "Review the requested change scope without modifying repository files.",
            "Inspect the repository, diff, tests, and evidence as needed, then return only JSON"
            " matching the provided schema.",
            "Bundled workflow guidance:",
            "\n\n".join(skill_parts),
            "Authoritative review request:",
            request.raw_markdown.strip(),
        ]
    )


def write_schema_file(schema: dict, directory: Path, mode: str) -> Path:
    """Materialize a schema file for the Codex CLI."""
    path = directory / f"{mode}-schema.json"
    path.write_text(json.dumps(schema, indent=2), encoding="utf-8")
    return path


def _resource_text(relative_path: str) -> str:
    with resources.as_file(resources.files(RESOURCE_ROOT).joinpath(relative_path)) as path:
        return path.read_text(encoding="utf-8").strip()


def _file_block(path: Path, display_path: str) -> str:
    return "\n".join(
        [
            f"### {display_path}",
            "```",
            path.read_text(encoding="utf-8"),
            "```",
        ]
    )


def _detect_language(repository: Path) -> str | None:
    if any(repository.rglob("*.py")):
        return "python"
    if any(repository.rglob("*.sh")):
        return "bash"
    if any(repository.rglob("*.cpp")) or any(repository.rglob("*.cc")):
        return "cpp"
    return None
